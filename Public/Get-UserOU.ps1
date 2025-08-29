function Get-UserOU {
<#
.SYNOPSIS
    Returns a user's parent OU/container in multiple useful formats.

.DESCRIPTION
    Looks up an AD user and derives the parent OU/container they live in.
    Outputs a structured object with DistinguishedName, CanonicalPath, LDAPPath,
    ADDrivePath, ContainerType, etc. Accepts pipeline input.

.PARAMETER User
    The user identity (sAMAccountName, UPN, DN, GUID, SID).
    Accepts pipeline input by value or by property name.

.PARAMETER Server
    Optional domain controller to query (passed to Get-ADUser -Server).
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Username','SamAccountName','UserPrincipalName','Identity','UPN')]
        [string]$User,

        [Parameter()]
        [string]$Server
    )

    begin {
        if (-not (Get-Command -Name Get-ADUser -ErrorAction SilentlyContinue)) {
            try { Import-Module ActiveDirectory -ErrorAction Stop }
            catch { throw "ActiveDirectory module not available. Install RSAT or import the module, then retry." }
        }

        function Convert-DNToCanonical {
            param([Parameter(Mandatory)][string]$Dn)
            $parts      = $Dn -split ','
            $domainPart = $parts | Where-Object { $_ -like 'DC=*' }
            $domain     = ( $domainPart | ForEach-Object { $_.Substring(3) } ) -join '.'

            $nonDomain  = $parts | Where-Object { $_ -notlike 'DC=*' } |
                          ForEach-Object { ($_ -split '=',2)[1] }

            if ($nonDomain.Count -gt 0) {
                $rev = @($nonDomain)
                [array]::Reverse($rev)
                if ([string]::IsNullOrWhiteSpace($domain)) {
                    ($rev -join '/')
                } else {
                    "$domain/$($rev -join '/')"
                }
            } else {
                $domain
            }
        }
    }

    process {
        try {
            $getParams = @{ Identity = $User; ErrorAction = 'Stop' }
            if ($Server) { $getParams.Server = $Server }

            $u = Get-ADUser @getParams -Properties DistinguishedName, CanonicalName, SamAccountName, UserPrincipalName

            $userDN = $u.DistinguishedName
            if (-not $userDN) {
                Write-Error "No DistinguishedName returned for '$User'." -ErrorAction Continue
                return
            }

            # Parent container DN (everything after the user's CN=... segment)
            $parentDN = ($userDN -split ',',2)[1]

            # Container type and leaf name (e.g., OU=Corp-Staff or CN=Users)
            $leafRDN = $parentDN.Split(',')[0]
            if ($leafRDN -like 'OU=*') {
                $containerType = 'OU'
            } else {
                $containerType = 'CN'
            }
            $leafName = ($leafRDN -split '=',2)[1]

            # Domain pieces (FIX: wrap pipelines in parentheses before -join)
            $domainDN   = ( ($parentDN -split ',') | Where-Object { $_ -like 'DC=*' } ) -join ','
            $domainName = ( ($parentDN -split ',') | Where-Object { $_ -like 'DC=*' } | ForEach-Object { $_.Substring(3) } ) -join '.'

            # Canonical form of the parent container
            $canonicalParent = Convert-DNToCanonical -Dn $parentDN

            [pscustomobject]@{
                User                  = $u.SamAccountName
                UserPrincipalName     = $u.UserPrincipalName
                UserDistinguishedName = $userDN

                ContainerType         = $containerType
                LeafContainerName     = $leafName

                DistinguishedName     = $parentDN
                CanonicalPath         = $canonicalParent
                LDAPPath              = "LDAP://$parentDN"
                ADDrivePath           = "AD:\$parentDN"

                Domain                = $domainName
                DomainDN              = $domainDN
            }
        }
        catch {
            Write-Error "Get-UserOU failed for '$User': $($_.Exception.Message)" -ErrorAction Continue
        }
    }
}


