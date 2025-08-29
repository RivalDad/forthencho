<#
.SYNOPSIS
Retrieves the source of the most recent Active Directory account lockout for a specified user.

.DESCRIPTION
The Get-ADLockoutSource function fetches the most recent lockout event for a specified user from the
domain controller's security logs. It ensures the 'ActiveDirectory' module is available by using your
Get-TempModule/Temp-SetupModule helper and then verifies with Test-ModuleVersion/Verify-ModuleVersion
before continuing.

.PARAMETER Username
The username of the AD account for which you want to check the lockout source.

.PARAMETER RequiredADModuleVersion
Optional minimum version requirement for the ActiveDirectory module. Defaults to 1.0.0.0.

.EXAMPLE
Get-ADLockoutSource -Username "jdoe"
This retrieves the most recent lockout event for the user "jdoe".
#>

import-module Forthencho
function Get-ADLockoutSource1 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter()]
        [Version]$RequiredADModuleVersion = '1.0.0'
    )

    # --- Ensure 'ActiveDirectory' module is available using your helpers ---
    $adModuleName = 'RSAT'

    # Prefer your session installer if available

    try {
            # Helpers may output $true/$false; we don't strictly depend on it here
            Get-TempModule -ModuleName 'ActiveDirectory.Toolbox' -RequiredVersion '1.0.0'
        } catch {
            Write-Verbose "Temp module setup failed: $($_.Exception.Message)"
        } else {
        Write-Verbose "No Get-TempModule/Temp-SetupModule helper found; will try direct import."
    }

    # Verify availability with your version tester (boolean OR object w/ IsCompliant)
    $tester = Get-Command -Name Test-ModuleVersion -ErrorAction SilentlyContinue
    if (-not $tester) {
        $tester = Get-Command -Name Verify-ModuleVersion -ErrorAction SilentlyContinue
    }

    $isReady = $false
    if ($tester) {
        try {
            $testResult = & $tester -ModuleName $adModuleName -RequiredVersion $RequiredADModuleVersion
            if ($testResult -is [bool]) {
                $isReady = $testResult
            } elseif ($null -ne $testResult -and $testResult.PSObject.Properties['IsCompliant']) {
                $isReady = [bool]$testResult.IsCompliant
            } else {
                # Last-resort truthiness
                $isReady = [bool]$testResult
            }
        } catch {
            Write-Verbose "Module version test failed: $($_.Exception.Message)"
            $isReady = $false
        }
    } else {
        # Fallback: try to import directly
        try {
            Import-Module -Name $adModuleName -MinimumVersion $RequiredADModuleVersion -ErrorAction Stop
            $isReady = $true
        } catch {
            $isReady = $false
        }
    }

    # Final attempt if not ready: import directly (covers RSAT-only availability)
    if (-not $isReady) {
        try {
            Import-Module -Name $adModuleName -MinimumVersion $RequiredADModuleVersion -ErrorAction Stop
            $isReady = $true
        } catch {
            throw "Required module '$adModuleName' (>= $RequiredADModuleVersion) is not available. Install RSAT or ensure the module path is accessible."
        }
    }

    # --- Proceed only once the module is confirmed available ---
    # Fetch the lockout event from the local Security log (event 4740), matching the username in the message
    # Note: This reads the local machine's Security log; run against a DC or adjust to query DC(s) as needed.
    $lockoutEvent =
        Get-EventLog -LogName Security -InstanceID 4740 -Newest 2000 |
        Where-Object { $_.Message -like "*$Username*" } |
        Sort-Object TimeGenerated -Descending |
        Select-Object -First 1

    if ($lockoutEvent) {
        Write-Host "Lockout event found for user $Username"
        Write-Host "--------------------------------------"
        Write-Host "Locked Out On: $($lockoutEvent.TimeGenerated)"
        Write-Host "Locked Out By: $($lockoutEvent.MachineName)"
        Write-Host "Event ID: $($lockoutEvent.EventID)"
        Write-Host "Message: $($lockoutEvent.Message)"
    } else {
        Write-Host "No recent lockout event found for user $Username"
    }
}
