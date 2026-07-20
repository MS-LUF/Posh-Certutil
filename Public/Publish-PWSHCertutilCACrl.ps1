function Publish-PWSHCertutilCACrl {
    <#
    .SYNOPSIS
        Publishes a new CRL on one or all CAs in a profile and returns the decoded CRL.
    .DESCRIPTION
        Connects to each CA in the profile via WinRM, runs certutil -crl to publish a new
        Certificate Revocation List, downloads the resulting CRL file, and returns it as a
        PowerShell object containing the raw CRL (Base64), publish output, and ASN.1-decoded
        CRL content via certutil -dump. Supports -WhatIf.
    .PARAMETER Profile
        The configuration profile to use. Optional; falls back to the profile marked as
        default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted. Throws if omitted
        and no default profile is configured.
    .PARAMETER CAFqdn
        Optional. Publishes on this CA only instead of all CAs in the profile.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Publish-PWSHCertutilCACrl -Profile 'prod-pki'
        Publishes a new CRL on every CA in the 'prod-pki' profile.
    .EXAMPLE
        Publish-PWSHCertutilCACrl -Profile 'prod-pki' -CAFqdn 'ca01.corp.local'
        Publishes a new CRL on ca01.corp.local only.
    .EXAMPLE
        Publish-PWSHCertutilCACrl -Profile 'prod-pki' -WhatIf
        Shows which CAs would have a CRL published without performing the action.
    .OUTPUTS
        PSCustomObject. Profile, CAServer, FileName, LastWriteTime, PublishOutput, CrlBase64, and CRLDecoded properties.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

        $cas = if ($PSBoundParameters.ContainsKey('CAFqdn')) {
            $found = $profileConfig.cas | Where-Object { $_.fqdn -eq $CAFqdn }
            if (-not $found) { throw "CA '$CAFqdn' is not defined in profile '$Profile'." }
            $found
        } else { $profileConfig.cas }

        foreach ($ca in $cas) {
            if (-not $PSCmdlet.ShouldProcess($ca.fqdn, 'Publish CRL')) { continue }
            try {
                $sessionArgs = @{ CAFqdn = $ca.fqdn; RemotingConfig = $profileConfig.remoting }
                if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
                $session = Get-CASession @sessionArgs

                $crlResult  = Invoke-CertutilCrl -Session $session
                $crlDecoded = ConvertFrom-CertutilAsn1 -CrlBase64 $crlResult.CrlBase64

                [PSCustomObject]@{
                    Profile       = $Profile
                    CAServer      = $ca.fqdn
                    FileName      = $crlResult.FileName
                    LastWriteTime = $crlResult.LastWriteTime
                    PublishOutput = $crlResult.PublishOutput
                    CrlBase64     = $crlResult.CrlBase64
                    CRLDecoded    = $crlDecoded
                }
            } catch {
                Write-Error "Failed to publish CRL on '$($ca.fqdn)': $_"
            }
        }
    }
}
