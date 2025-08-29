function Test-ModuleVersion {
<#
.SYNOPSIS
    Verifies that a specific module is installed at or above the required version.

.DESCRIPTION
    Checks if a module is installed in the current session (or available on disk)
    and compares the installed version to the required version.
    Outputs a structured object with properties, which can be piped into
    other functions or used in conditional logic.

.PARAMETER ModuleName
    The name of the module to check.

.PARAMETER RequiredVersion
    The minimum version number of the module that must be present.

.EXAMPLE
    Verify-ModuleVersion -ModuleName "Az" -RequiredVersion "11.5.0"

    # Returns an object like:
    # ModuleName   RequiredVersion InstalledVersion IsCompliant
    # ----------   --------------- ---------------- -----------
    # Az           11.5.0          11.7.0           True

.EXAMPLE
    Verify-ModuleVersion -ModuleName "Az" -RequiredVersion "11.5.0" |
        Where-Object { -not $_.IsCompliant }

    # Pipeline usage to filter non-compliant modules.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [Version]$RequiredVersion
    )

    process {
        try {
            # Get installed module(s)
            $installedModules = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue

            if (-not $installedModules) {
                [PSCustomObject]@{
                    ModuleName       = $ModuleName
                    RequiredVersion  = $RequiredVersion
                    InstalledVersion = $null
                    IsCompliant      = $false
                }
                return
            }

            # Find the highest installed version
            $highestVersion = ($installedModules | Sort-Object Version -Descending | Select-Object -First 1).Version

            [PSCustomObject]@{
                ModuleName       = $ModuleName
                RequiredVersion  = $RequiredVersion
                InstalledVersion = $highestVersion
                IsCompliant      = ($highestVersion -ge $RequiredVersion)
            }
        }
        catch {
            Write-Error "Error checking module version: $($_.Exception.Message)"
        }
    }
}
