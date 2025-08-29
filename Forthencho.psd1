@{
  RootModule = 'Forthencho'
  ModuleVersion = '0.0.11'
  GUID = '0bdb27e1-ffbe-4470-bc95-01cf17613a9d'
  Author = 'Everett Williams'
  CompanyName = 'Forthencho'
  Copyright = '(c) Everett Williams. All rights reserved.'
  Description = 'This is a test module'

  CompatiblePSEditions = @('Desktop','Core')
  PowerShellVersion    = '5.1'

  # Export explicitly (update these names as your module grows)
  FunctionsToExport = @('Forthencho','Test-ModuleVersion','Get-TempModule','Remove-TempModule','Get-ADLockoutSource','Ensure-RSAT','Get-UserOU')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      # Tags       = @('Networking','Ping','Diagnostics')
      # ProjectUri = 'https://github.com/you/Test-Forthencho'
      # LicenseUri = 'https://github.com/you/Test-Forthencho/blob/main/LICENSE'
      # ReleaseNotes = '...'
    }
  }
}
