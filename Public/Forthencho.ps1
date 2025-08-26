function Test-Forthencho {
    <#
    .SYNOPSIS
        Ping forthencho.com.

    .DESCRIPTION
        Uses Test-Connection to send ICMP echo requests to forthencho.com.
        Supports a quiet (boolean) result or full ping output.

    .PARAMETER Count
        Number of echo requests to send (default 4).

    .PARAMETER TimeoutMs
        Timeout per ping in milliseconds (default 1000).

    .PARAMETER Quiet
        Return $true/$false instead of full results.

    .EXAMPLE
        Test-Forthencho
    .EXAMPLE
        Test-Forthencho -Quiet
    .EXAMPLE
        Test-Forthencho -Count 10 -TimeoutMs 2000
    #>
    [CmdletBinding()]
    param(
        [int]$Count = 4,
        [switch]$Quiet
    )

    $target = 'forthencho.com'

    if ($Quiet) {
        return Test-Connection $target -Count $Count -Quiet
    }

    Test-Connection  $target -Count $Count 
}
Export-ModuleMember -Function Test-Forthencho