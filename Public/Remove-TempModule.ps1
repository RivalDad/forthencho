function Remove-TempModule {
<#
.SYNOPSIS
    Removes session-temporary module copies and unloads them from the session.

.DESCRIPTION
    Targets the session temp module location used by Temp-SetupModule
    (a folder named like 'ForthenchoModules_yyyyMMdd_HHmmss_fff' that was added
    to PSModulePath). For each input module:
      1. Attempts Remove-Module to unload it from the session.
      2. Removes any matching temp copy under the session temp root.
      3. Outputs $true if the module is still available on PSModulePath
         (or if a RequiredVersion is given, if an installed version >= RequiredVersion exists),
         otherwise $false.

.PARAMETER ModuleName
    Name of the module to remove from the session temp store.
    Accepts pipeline input by value or property name.

.PARAMETER RequiredVersion
    Optional. If provided, availability is evaluated as
    "any installed version >= RequiredVersion".

.PARAMETER All
    If specified, deletes ALL modules under the session temp root.
    If ModuleName is also provided, -All behaves the same but then
    only the specific ModuleName is evaluated for availability.

.EXAMPLE
    'Pester','ExchangeOnlineManagement' | Delete-TempModule

.EXAMPLE
    [PSCustomObject]@{ ModuleName='Pester'; RequiredVersion='5.5.0' } |
        Delete-TempModule -Verbose

.EXAMPLE
    # Remove everything saved by Temp-SetupModule in this session
    Remove-TempModule -All -Verbose
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$ModuleName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Version','MinimumVersion')]
        [Version]$RequiredVersion,

        [Parameter()]
        [switch]$All
    )

    begin {
        # Try to find the session temp module root used by Temp-SetupModule.
        # 1) Prefer the module-scoped variable if present (same module file)
        # 2) Otherwise, scan PSModulePath for a folder with our naming pattern.
        $script:SessionModuleRoot = $script:SessionModuleRoot  # preserve if set

        if (-not $script:SessionModuleRoot -or -not (Test-Path $script:SessionModuleRoot)) {
            $paths = $env:PSModulePath -split ';'
            foreach ($p in $paths) {
                try {
                    if ([string]::IsNullOrWhiteSpace($p)) { continue }
                    $leaf = Split-Path $p -Leaf
                    if ($leaf -like 'ForthenchoModules_*' -and (Test-Path $p)) {
                        $script:SessionModuleRoot = $p
                        break
                    }
                } catch { }
            }
        }

        if (-not $script:SessionModuleRoot -or -not (Test-Path $script:SessionModuleRoot)) {
            Write-Verbose "No session temp module root found. Nothing to delete."
        }
    }

    process {
        # Optionally purge ALL temp modules (once).
        if ($All.IsPresent -and $script:SessionModuleRoot -and (Test-Path $script:SessionModuleRoot)) {
            if ($PSCmdlet.ShouldProcess($script:SessionModuleRoot, "Remove all temp modules")) {
                try {
                    # Try to unload any modules currently loaded from this root
                    Get-Module | Where-Object {
                        $_.ModuleBase -like (Join-Path $script:SessionModuleRoot '*')
                    } | ForEach-Object {
                        try { Remove-Module -Name $_.Name -Force -ErrorAction SilentlyContinue } catch { }
                    }

                    # Delete the entire temp root contents (not the root itself to keep PSModulePath sane)
                    Get-ChildItem -LiteralPath $script:SessionModuleRoot -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Verbose "Cleared all content under: $script:SessionModuleRoot"
                } catch {
                    Write-Verbose "Failed to clear all temp modules: $($_.Exception.Message)"
                }
            }
        }

        # If no specific ModuleName provided, and -All handled above, stop here.
        if (-not $ModuleName) { return }

        # Try to unload from session first
        try {
            $loaded = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue
            if ($loaded) {
                foreach ($m in $loaded) {
                    # Be gentle: only remove if it looks like it came from temp root or user explicitly wants it gone.
                    if ($m.ModuleBase -and $script:SessionModuleRoot -and ($m.ModuleBase -like (Join-Path $script:SessionModuleRoot '*'))) {
                        if ($PSCmdlet.ShouldProcess($ModuleName, "Remove-Module (temp-loaded)")) {
                            Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        # It's loaded from another path; we still may remove temp copies below
                        Write-Verbose "'$ModuleName' is loaded from a non-temp path: $($m.ModuleBase)"
                    }
                }
            }
        } catch {
            Write-Verbose "Remove-Module '$ModuleName' failed or not loaded: $($_.Exception.Message)"
        }

        # Delete temp copy on disk (under session root), optionally target specific version
        if ($script:SessionModuleRoot -and (Test-Path $script:SessionModuleRoot)) {
            $moduleDir = Join-Path $script:SessionModuleRoot $ModuleName
            if (Test-Path $moduleDir) {
                try {
                    if ($RequiredVersion) {
                        $verDir = Join-Path $moduleDir ($RequiredVersion.ToString())
                        if (Test-Path $verDir) {
                            if ($PSCmdlet.ShouldProcess($verDir, "Remove temp module version")) {
                                Remove-Item -LiteralPath $verDir -Recurse -Force -ErrorAction SilentlyContinue
                                Write-Verbose "Removed temp '$ModuleName' $RequiredVersion from: $verDir"
                            }
                        } else {
                            Write-Verbose "No temp directory for '$ModuleName' version $RequiredVersion at: $verDir"
                        }

                        # If module folder now empty, remove it
                        if ((Get-ChildItem -LiteralPath $moduleDir -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                            Remove-Item -LiteralPath $moduleDir -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        if ($PSCmdlet.ShouldProcess($moduleDir, "Remove all temp versions for module")) {
                            Remove-Item -LiteralPath $moduleDir -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Verbose "Removed all temp versions for '$ModuleName' from: $moduleDir"
                        }
                    }
                } catch {
                    Write-Verbose "Failed to remove temp files for '$ModuleName': $($_.Exception.Message)"
                }
            } else {
                Write-Verbose "No temp folder found for '$ModuleName' at: $moduleDir"
            }
        } else {
            Write-Verbose "No session temp root available; skipping disk cleanup for '$ModuleName'."
        }

        # Determine availability after cleanup
        try {
            $installed = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
                         Sort-Object Version -Descending
            $isAvailable =
                if (-not $installed) {
                    $false
                } elseif ($RequiredVersion) {
                    ($installed[0].Version -ge $RequiredVersion)
                } else {
                    $true
                }

            # Emit boolean to pipeline
            $isAvailable
        } catch {
            Write-Verbose "Availability check failed for '$ModuleName': $($_.Exception.Message)"
            $false
        }
    }

    end {
        # Optionally, if the temp root is now empty, you could clean it and remove from PSModulePath.
        try {
            if ($script:SessionModuleRoot -and (Test-Path $script:SessionModuleRoot)) {
                $remaining = Get-ChildItem -LiteralPath $script:SessionModuleRoot -Force -ErrorAction SilentlyContinue
                if (-not $remaining) {
                    Write-Verbose "Session temp module root is empty: $script:SessionModuleRoot"
                    # Leave the directory and PSModulePath entry in place for future runs within this session.
                    # (Safer: other code may still depend on it.)
                }
            }
        } catch { }
    }
}
