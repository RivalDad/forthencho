function Get-TempModule {
<#
.SYNOPSIS
    Temporarily makes a specific module version available for the current session.

.DESCRIPTION
    Checks if the requested module (at or above the required version) is already installed.
    If not, it downloads the exact required version to a session-scoped temp folder and imports it.
    The temp folder is added to PSModulePath for this session only.
    Outputs $true if the module is available (imported or already present), else $false.

.PARAMETER ModuleName
    The module name to set up. Accepts pipeline input by value or by property name.

.PARAMETER RequiredVersion
    The exact version required if a download is needed. If a higher version is already installed,
    that satisfies the requirement and will be used. Accepts pipeline input by property name.

.PARAMETER Repository
    The repository to use with Save-Module when downloading. Defaults to 'PSGallery'.

.EXAMPLE
    Get-TempModule -ModuleName 'ActiveDirectory.Toolbox' -RequiredVersion '1.0.0'

.EXAMPLE
    'Az','Microsoft.Graph' | Get-TempModule -RequiredVersion '2.0.0' -Verbose

.EXAMPLE
    [PSCustomObject]@{ ModuleName='Pester'; RequiredVersion='5.5.0' } |
        Get-TempModule -Repository PSGallery
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$ModuleName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Version','MinimumVersion')]
        [Version]$RequiredVersion,

        [Parameter()]
        [string]$Repository = 'PSGallery'
    )

    begin {
        # Create a per-session temp module root and prepend to PSModulePath once.
        $script:SessionModuleRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("ForthenchoModules_{0:yyyyMMdd_HHmmss_fff}" -f (Get-Date))
        if (-not (Test-Path $script:SessionModuleRoot)) {
            New-Item -Path $script:SessionModuleRoot -ItemType Directory -Force | Out-Null
            Write-Verbose "Created session module root: $script:SessionModuleRoot"
        }

        if (-not ($env:PSModulePath -split ';' | Where-Object { $_ -eq $script:SessionModuleRoot })) {
            $env:PSModulePath = $script:SessionModuleRoot + ';' + $env:PSModulePath
            Write-Verbose "Prepended to PSModulePath for this session: $script:SessionModuleRoot"
        }
    }

    process {
        try {
            Write-Verbose "Checking module '$ModuleName' for required version $RequiredVersion ..."

            # 1) Prefer an already-installed version that meets or exceeds the requirement.
            $installed = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
                         Sort-Object Version -Descending
            if ($installed) {
                $highest = $installed[0].Version
                if ($highest -ge $RequiredVersion) {
                    Write-Verbose "Found installed '$ModuleName' $highest (>= $RequiredVersion). Importing..."
                    try {
                        Import-Module -Name $ModuleName -MinimumVersion $RequiredVersion -Force -ErrorAction Stop | Out-Null
                        Write-Verbose "'$ModuleName' imported from installed modules."
                        # Output $true for this input item
                        $true
                        return
                    } catch {
                        Write-Verbose "Installed module present but import failed: $($_.Exception.Message)"
                        # fall through to try a temp copy
                    }
                } else {
                    Write-Verbose "Installed '$ModuleName' version $highest is below required $RequiredVersion."
                }
            } else {
                Write-Verbose "No installed versions of '$ModuleName' found."
            }

            # 2) Download exact version to the session temp root and import.
            $targetPath = Join-Path $script:SessionModuleRoot $ModuleName
            if (-not (Test-Path $targetPath)) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
            }

            Write-Verbose "Attempting to download '$ModuleName' $RequiredVersion to: $targetPath"
            try {
                # Ensure PowerShellGet/NuGet provider can operate (common failure point is provider missing)
                if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                    Write-Verbose "NuGet provider not found. Installing silently..."
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
                }

                # Save-Module avoids permanent install; we keep it session-scoped.
                Save-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $Repository -Path $targetPath -Force -ErrorAction Stop
            } catch {
                Write-Verbose "Save-Module failed: $($_.Exception.Message)"
                $false
                return
            }

            # Import from the freshly saved version
            $savedModulePath = Get-ChildItem -Path (Join-Path $targetPath $ModuleName) -Directory -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -eq $RequiredVersion.ToString() } |
                               Select-Object -First 1

            if (-not $savedModulePath) {
                Write-Verbose "Downloaded path for '$ModuleName' $RequiredVersion not found under $targetPath."
                $false
                return
            }

            try {
                Import-Module -Name $savedModulePath.FullName -Force -ErrorAction Stop | Out-Null
                Write-Verbose "Imported '$ModuleName' from session temp location: $($savedModulePath.FullName)"
                $true
            } catch {
                Write-Verbose "Import from temp failed: $($_.Exception.Message)"
                $false
            }
        }
        catch {
            Write-Verbose "Unhandled error: $($_.Exception.Message)"
            $false
        }
    }
}
