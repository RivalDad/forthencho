# Load helpers first (optional but common)
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Load public functions
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Export only the public functions (by filename base)
$public = (Get-ChildItem (Join-Path $PSScriptRoot 'Public') -Filter *.ps1).BaseName
Export-ModuleMember -Function $public
