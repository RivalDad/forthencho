function Ensure-RSAT {
<#
.SYNOPSIS
    Ensures RSAT tools are installed. Installs if missing.

.DESCRIPTION
    On Windows 10 1809+ / Windows 11 (client): installs RSAT via Features on Demand (WindowsCapabilities).
    On Windows Server: installs RSAT via Windows Features (Install-WindowsFeature).

    By default, this ensures the Active Directory RSAT tools (for the 'ActiveDirectory' PS module).
    Use -All to install all RSAT components available on the platform.

    Returns $true if the requested RSAT tools are available after the operation, otherwise $false.

.PARAMETER All
    Install all RSAT components (instead of just AD DS/AD LDS tools).

.PARAMETER BypassWSUS
    On client OS only: temporarily disables WSUS usage for the install (common fix for 0x800f0954),
    attempts the install from Windows Update, then restores the original setting.

.PARAMETER MinADModuleVersion
    Minimum version of the 'ActiveDirectory' PowerShell module to consider as available. Default: 1.0.0.0

.EXAMPLE
    Ensure-RSAT
    # Ensures Active Directory RSAT tools are present. Installs if needed.

.EXAMPLE
    Ensure-RSAT -All -Verbose
    # Installs all RSAT tools (client: all Rsat.* capabilities; server: all RSAT-* features).

.EXAMPLE
    Ensure-RSAT -BypassWSUS
    # Temporarily bypass WSUS to fetch RSAT FODs from Windows Update (client OS only).

.NOTES
    Requires administrative privileges.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [switch]$All,
        [switch]$BypassWSUS,
        [Version]$MinADModuleVersion = '1.0.0.0'
    )

    # --- Helpers ---
    function Test-IsAdmin {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $pr = New-Object Security.Principal.WindowsPrincipal($id)
            return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch { return $false }
    }

    function Test-ADModuleAvailable {
        param([Version]$MinVersion = '1.0.0.0')
        $m = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue |
             Sort-Object Version -Descending |
             Select-Object -First 1
        return ($m -and $m.Version -ge $MinVersion)
    }

    # --- Preflight ---
    if (-not (Test-IsAdmin)) {
        Write-Error "Ensure-RSAT must be run from an elevated (Administrator) PowerShell session."
        return $false
    }

    # Already good?
    if (-not $All) {
        if (Test-ADModuleAvailable -MinVersion $MinADModuleVersion) {
            Write-Verbose "ActiveDirectory module already available at required version."
            return $true
        }
    }

    $os = Get-CimInstance Win32_OperatingSystem
    $isServer = ($os.ProductType -ne 1)  # 1 = Workstation, 2/3 = Domain Controller/Server
    $build   = [int]$os.BuildNumber

    # For client installs, we may need to bypass WSUS to avoid 0x800f0954.
    $wuRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $originalUseWUServer = $null
    $changedWSUS = $false

    try {
        if ($isServer) {
            # -------------------------
            # Windows Server (2016/2019/2022)
            # -------------------------
            Import-Module ServerManager -ErrorAction SilentlyContinue

            if ($All) {
                $rsatFeatures = Get-WindowsFeature -Name RSAT* -ErrorAction SilentlyContinue |
                                Where-Object { $_.InstallState -ne 'Installed' } |
                                Select-Object -ExpandProperty Name
                if ($rsatFeatures.Count -eq 0) {
                    Write-Verbose "All RSAT features already installed."
                } else {
                    if ($PSCmdlet.ShouldProcess("Server RSAT features", "Install $($rsatFeatures -join ', ')")) {
                        Install-WindowsFeature -Name $rsatFeatures -IncludeAllSubFeature -ErrorAction Stop | Out-Null
                    }
                }
                # Validate: if All, success = AD module available OR at least some RSAT features installed
                return (Test-ADModuleAvailable -MinVersion $MinADModuleVersion) -or
                       ((Get-WindowsFeature -Name RSAT* | Where-Object InstallState -eq 'Installed').Count -gt 0)
            }
            else {
                # Just the AD PowerShell module / tools
                $target = @('RSAT-AD-PowerShell','RSAT-AD-AdminCenter','RSAT-AD-Tools') |
                          Where-Object { (Get-WindowsFeature -Name $_ -ErrorAction SilentlyContinue).InstallState -ne 'Installed' }
                if ($target) {
                    if ($PSCmdlet.ShouldProcess("Active Directory RSAT", "Install $($target -join ', ')")) {
                        Install-WindowsFeature -Name $target -IncludeAllSubFeature -ErrorAction Stop | Out-Null
                    }
                } else {
                    Write-Verbose "AD RSAT features already installed."
                }
                return (Test-ADModuleAvailable -MinVersion $MinADModuleVersion)
            }
        }
        else {
            # -------------------------
            # Windows Client (Win10/11)
            # -------------------------
            if ($build -lt 17763) {
                Write-Warning "This client OS is pre-1809 (build $build). RSAT is not a Feature on Demand here. Please download and install the RSAT package from Microsoft manually."
                return (Test-ADModuleAvailable -MinVersion $MinADModuleVersion)
            }

            # Work around WSUS if requested
            if ($BypassWSUS) {
                try {
                    if (Test-Path $wuRegPath) {
                        $originalUseWUServer = (Get-ItemProperty -Path $wuRegPath -Name UseWUServer -ErrorAction SilentlyContinue).UseWUServer
                    }
                    New-Item -Path $wuRegPath -Force | Out-Null
                    Set-ItemProperty -Path $wuRegPath -Name UseWUServer -Value 0 -Type DWord
                    Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                    $changedWSUS = $true
                    Write-Verbose "Temporarily disabled WSUS for Features on Demand installation."
                } catch {
                    Write-Warning "Could not modify WSUS setting: $($_.Exception.Message)"
                }
            }

            # Decide which capabilities to install
            if ($All) {
                $caps = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'Rsat.*' -and $_.State -ne 'Installed' }
                if (-not $caps) {
                    Write-Verbose "All RSAT capabilities already installed."
                } else {
                    foreach ($c in $caps) {
                        if ($PSCmdlet.ShouldProcess($c.Name, "Add-WindowsCapability")) {
                            try {
                                Add-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null
                                Write-Verbose "Installed: $($c.Name)"
                            } catch {
                                Write-Warning "Failed: $($c.Name) - $($_.Exception.Message)"
                            }
                        }
                    }
                }
                # Validate: AD module available OR all Rsat.* report Installed
                return (Test-ADModuleAvailable -MinVersion $MinADModuleVersion) -or
                       -not (Get-WindowsCapability -Online | Where-Object { $_.Name -like 'Rsat.*' -and $_.State -ne 'Installed' })
            }
            else {
                # Ensure only AD DS/AD LDS tools (contains the AD module)
                $adCapName = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
                $state = (Get-WindowsCapability -Online -Name $adCapName -ErrorAction SilentlyContinue).State
                if ($state -ne 'Installed') {
                    if ($PSCmdlet.ShouldProcess($adCapName, "Add-WindowsCapability")) {
                        Add-WindowsCapability -Online -Name $adCapName -ErrorAction Stop | Out-Null
                        Write-Verbose "Installed capability: $adCapName"
                    }
                } else {
                    Write-Verbose "Capability already installed: $adCapName"
                }
                return (Test-ADModuleAvailable -MinVersion $MinADModuleVersion)
            }
        }
    }
    catch {
        Write-Error "Ensure-RSAT failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        # Restore WSUS setting if we changed it
        if ($changedWSUS) {
            try {
                if ($null -eq $originalUseWUServer) {
                    Remove-ItemProperty -Path $wuRegPath -Name UseWUServer -ErrorAction SilentlyContinue
                } else {
                    Set-ItemProperty -Path $wuRegPath -Name UseWUServer -Value $originalUseWUServer -Type DWord -ErrorAction SilentlyContinue
                }
                Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                Write-Verbose "Restored WSUS configuration."
            } catch {
                Write-Warning "Failed to restore WSUS config: $($_.Exception.Message)"
            }
        }
    }
}
