function Forthencho {
<#
.SYNOPSIS
    Interactive launcher for module functions.

.DESCRIPTION
    Displays a simple menu, greets the user, and asks which function to run.
    Users can choose by number or type the function name directly.
    Easy to extend: pass your own -Functions list or update the default array.

.PARAMETER Functions
    The list of function names to present in the menu. Defaults to common Forthencho items.

.EXAMPLE
    Forthencho
    # Shows the menu with the default five functions.

.EXAMPLE
    Forthencho -Functions 'Foo','Bar','Baz'
    # Shows a menu for your custom set.
#>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Functions = @(
            'Verify-ModuleVersion',
            'Temp-SetupModule',
            'Delete-TempModule',
            'ping-Forthencho',
            'Hello-World'
        )
    )

    # Local helper: render the menu
    function _Show-Menu {
        Clear-Host
        Write-Host '========================================='
        Write-Host '   Hello! Welcome to the Forthencho Hub   '
        Write-Host '========================================='
        Write-Host ''
        Write-Host 'What would you like to run?'
        Write-Host ''

        for ($i = 0; $i -lt $Functions.Count; $i++) {
            $n = $i + 1
            Write-Host (" {0,2}. {1}" -f $n, $Functions[$i])
        }

        Write-Host ''
        Write-Host 'Enter a number or function name.'
        Write-Host 'Type R to refresh, or Q to quit.'
        Write-Host ''
    }

    # Resolve a user selection (number or name) to a function name
    function Resolve-Selection {
        param([string]$Input)
        if ([string]::IsNullOrWhiteSpace($Input)) { return $null }

        # Number -> index
        if ($Input -as [int]) {
            $idx = [int]$Input - 1
            if ($idx -ge 0 -and $idx -lt $Functions.Count) {
                return $Functions[$idx]
            } else {
                return $null
            }
        }

        # Direct name -> match (case-insensitive)
        $match = $Functions | Where-Object { $_ -ieq $Input }
        if ($match) { return $match[0] }

        # Partial match convenience (starts with)
        $starts = $Functions | Where-Object { $_ -like "$Input*" }
        if ($starts.Count -eq 1) { return $starts[0] }

        return $null
    }

    # Main loop
    while ($true) {
        _Show-Menu
        $choice = Read-Host -Prompt 'Your choice'

        switch -Regex ($choice) {
            '^(?i)q$' { Write-Host 'Goodbye!'; break }
            '^(?i)r$' { continue }
            default {
                $target = _Resolve-Selection -Input $choice
                if (-not $target) {
                    Write-Warning "Could not understand selection: '$choice'"
                    Start-Sleep -Milliseconds 900
                    continue
                }

                # Verify the function exists before trying to invoke it
                $cmd = Get-Command -Name $target -CommandType Function -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    Write-Warning "'$target' is not defined yet in this session/module."
                    Write-Host   "Tip: add the function to your module or dot-source it, then choose it again."
                    Start-Sleep -Milliseconds 1200
                    continue
                }

                Write-Host ''
                Write-Host ">>> Running: $target" -ForegroundColor Cyan
                Write-Host '--------------------------------------------------'

                try {
                    & $target
                } catch {
                    Write-Error "An error occurred while running '$target': $($_.Exception.Message)"
                }

                Write-Host '--------------------------------------------------'
                Write-Host "<<< Completed: $target" -ForegroundColor Cyan
                Write-Host ''
                Read-Host 'Press Enter to return to the menu' | Out-Null
            }
        }
    }
}
