function Get-PWSHCertutilRevokedCerts {
    <#
    .SYNOPSIS
        Gets revoked certificates from one or all CAs in a profile.
    .DESCRIPTION
        Connects to each CA in the profile via WinRM, runs certutil -view filtered to
        revoked certificates (Disposition=21), and returns them as PowerShell objects.
        Each result carries Profile and CAServer metadata.
    .PARAMETER Profile
        The configuration profile to use. Optional; falls back to the profile marked as
        default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted. Throws if omitted
        and no default profile is configured.
    .PARAMETER CAFqdn
        Optional. Queries only this CA instead of all CAs in the profile.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Get-PWSHCertutilRevokedCerts -Profile 'prod-pki'
        Retrieves all revoked certificates from every CA in the 'prod-pki' profile.
    .EXAMPLE
        Get-PWSHCertutilRevokedCerts -Profile 'prod-pki' | Group-Object RevokedReason
        Groups revoked certificates by revocation reason.
    .OUTPUTS
        PSCustomObject[]. One object per revoked certificate with Profile, CAServer, and all configured -out fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string] $CAFqdn,

        [Parameter()]
        [pscredential] $Credential
    )

    dynamicparam {
        New-ProfileDynamicParameter
    }

    process {
        $Profile = $PSBoundParameters['Profile']

        $config        = Read-ConfigFile
        $Profile       = Resolve-ProfileName -Config $config -ProfileName $Profile
        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $autoSyncArgs = @{ Config = $config; ProfileName = $Profile; ProfileConfig = $profileConfig }
        if ($PSBoundParameters.ContainsKey('Credential')) { $autoSyncArgs['Credential'] = $Credential }
        $profileConfig = Invoke-ProfileAutoSync @autoSyncArgs

        $fieldMap = @{}
        if ($profileConfig.syncState -and $profileConfig.syncState.fieldNameMap) {
            $profileConfig.syncState.fieldNameMap.PSObject.Properties |
                ForEach-Object { $fieldMap[$_.Name] = $_.Value }
        }

        $viewParams = Get-CertutilViewParams -ProfileConfig $profileConfig -Operation 'revokedCerts'

        $cas = if ($PSBoundParameters.ContainsKey('CAFqdn')) {
            $found = $profileConfig.cas | Where-Object { $_.fqdn -eq $CAFqdn }
            if (-not $found) { throw "CA '$CAFqdn' is not defined in profile '$Profile'." }
            $found
        } else { $profileConfig.cas }

        foreach ($ca in $cas) {
            try {
                $sessionArgs = @{ CAFqdn = $ca.fqdn; RemotingConfig = $profileConfig.remoting }
                if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }

                $session   = Get-CASession @sessionArgs
                $caCulture = Get-CACulture -Session $session
                $rawOutput = Invoke-CertutilView -Session $session -Restrict $viewParams.Restrict -Out $viewParams.Out
                ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap -CACulture $caCulture |
                    Add-ResultMetadata -Profile $Profile -CAServer $ca.fqdn
            } catch {
                Write-Error "Failed to query revoked certs from '$($ca.fqdn)': $_"
            }
        }
    }
}
