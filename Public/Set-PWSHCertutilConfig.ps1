function Set-PWSHCertutilConfig {
    <#
    .SYNOPSIS
        Creates or updates a profile in the Posh-Certutil JSON configuration.
    .DESCRIPTION
        Writes or updates a named profile in Posh-Certutil.json. The certutil -restrict and
        -out values for each operation are pre-populated with defaults; edit the JSON file
        directly to customise them after creation. Supports -WhatIf.
    .PARAMETER Profile
        Name of the profile to create or update.
    .PARAMETER CAFqdn
        One or more CA FQDNs to include in this profile.
    .PARAMETER DisplayName
        Optional display name for each CA, in the same order as -CAFqdn. Defaults to the FQDN.
    .PARAMETER Description
        Optional description for this profile.
    .PARAMETER UseTls
        Use HTTPS (port 5986) for WinRM. Default: $true.
    .PARAMETER Port
        WinRM port. Defaults to 5986 when -UseTls is $true, 5985 otherwise.
    .PARAMETER MaxSessionsPerCA
        Maximum concurrent WinRM sessions per CA server. Default: 2.
    .PARAMETER DefaultProfile
        Marks this profile as the default profile used by other cmdlets when -Profile is
        omitted. Only one profile can be default at a time; setting this to $true clears the
        flag on any other profile. If omitted while updating an existing profile, the
        profile's current default status is preserved. Default: $false for new profiles.
    .EXAMPLE
        Set-PWSHCertutilConfig -Profile 'prod-pki' -CAFqdn 'ca01.corp.local','ca02.corp.local' -UseTls $true -Description 'Production PKI'
        Creates the 'prod-pki' profile with two CAs using TLS.
    .EXAMPLE
        Set-PWSHCertutilConfig -Profile 'lab' -CAFqdn 'ca-lab.lab.local' -UseTls $false
        Creates a non-TLS lab profile.
    .EXAMPLE
        Set-PWSHCertutilConfig -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -DefaultProfile $true
        Marks 'prod-pki' as the default profile so other cmdlets can omit -Profile.
    .OUTPUTS
        PSCustomObject. The saved profile as returned by Get-PWSHCertutilConfig.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Profile,

        [Parameter(Mandatory)]
        [string[]] $CAFqdn,

        [Parameter()]
        [string[]] $DisplayName,

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [bool] $UseTls = $true,

        [Parameter()]
        [int] $Port,

        [Parameter()]
        [int] $MaxSessionsPerCA = 2,

        [Parameter()]
        [bool] $DefaultProfile
    )

    if (-not $PSBoundParameters.ContainsKey('Port')) {
        if ($UseTls) { $Port = 5986 } else { $Port = 5985 }
    }

    $config          = Read-ConfigFile
    $existingProfile = $null
    if ($config.profiles.PSObject.Properties.Name -contains $Profile) {
        $existingProfile = $config.profiles.$Profile
    }

    $isDefault = if ($PSBoundParameters.ContainsKey('DefaultProfile')) {
        $DefaultProfile
    } elseif ($existingProfile -and $existingProfile.defaultProfile) {
        $true
    } else {
        $false
    }

    $cas = for ($i = 0; $i -lt $CAFqdn.Count; $i++) {
        [ordered]@{
            fqdn        = $CAFqdn[$i]
            displayName = if ($DisplayName -and $i -lt $DisplayName.Count) { $DisplayName[$i] } else { $CAFqdn[$i] }
        }
    }

    $profileEntry = [ordered]@{
        description    = $Description
        defaultProfile = $isDefault
        remoting       = [ordered]@{
            useTls           = $UseTls
            port             = $Port
            maxSessionsPerCA = $MaxSessionsPerCA
        }
        cas            = @($cas)
        certutilView   = [ordered]@{
            restrict = [ordered]@{
                issuedCerts   = 'GeneralFlags=0,Disposition=20'
                revokedCerts  = 'Disposition=21'
                expiringCerts = 'GeneralFlags=0,Disposition=20,NotAfter>={TODAY},NotAfter<={EXPIRE_DATE}'
                search        = '{DYNAMIC}'
            }
            out      = [ordered]@{
                issuedCerts   = @('RequestID','RequesterName','CommonName','NotBefore','NotAfter','CertificateTemplate','SerialNumber')
                revokedCerts  = @('RequestID','RequesterName','CommonName','NotBefore','NotAfter','SerialNumber','RevokedReason','RevokedEffectiveWhen')
                expiringCerts = @('RequestID','RequesterName','CommonName','NotAfter','CertificateTemplate','SerialNumber')
                search        = @('RequestID','RequesterName','CommonName','NotBefore','NotAfter','CertificateTemplate','SerialNumber','RevokedReason','RevokedEffectiveWhen')
            }
        }
        syncState      = $null
    }

    if ($PSCmdlet.ShouldProcess($Profile, 'Create or update profile in Posh-Certutil.json')) {
        $config.profiles | Add-Member -MemberType NoteProperty -Name $Profile -Value $profileEntry -Force
        if ($isDefault) {
            foreach ($name in $config.profiles.PSObject.Properties.Name) {
                if ($name -ne $Profile -and $config.profiles.$name.defaultProfile) {
                    $config.profiles.$name.defaultProfile = $false
                }
            }
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigPath -Encoding UTF8
        Write-Verbose "Profile '$Profile' written to $script:ConfigPath"
        Get-PWSHCertutilConfig -Profile $Profile
    }
}
