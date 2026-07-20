function Get-PWSHCertreqCert {
    <#
    .SYNOPSIS
        Retrieves an issued certificate from a CA by request ID.
    .DESCRIPTION
        Connects to the specified CA via WinRM and runs certreq -retrieve to download
        a previously-submitted certificate. Accepts pipeline input from Submit-PWSHCertreqCSR
        so a pending request object can be piped directly after an administrator approves it.

        When the request is still in Pending state the cmdlet returns an object with
        Status='Pending' and no Certificate. When the certificate has been issued the
        Certificate property carries the ASN.1-decoded certificate.
    .PARAMETER InputObject
        A request object with Profile, CAServer, and RequestID properties.
        Accepts output from Submit-PWSHCertreqCSR.
    .PARAMETER Profile
        The configuration profile. Optional in the Direct parameter set; falls back to the
        profile marked as default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted.
        Throws if omitted and no default profile is configured.
    .PARAMETER CAFqdn
        The CA where the request was submitted. Required in the Direct parameter set.
    .PARAMETER RequestID
        The request ID to retrieve. Required in the Direct parameter set.
    .PARAMETER OutputCertPath
        Optional. When the certificate is issued, save the DER-encoded certificate to
        this local file path.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to the current user.
    .EXAMPLE
        $pending | Get-PWSHCertreqCert
        Retrieves the certificate for a pending request returned by Submit-PWSHCertreqCSR.
    .EXAMPLE
        Get-PWSHCertreqCert -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -RequestID '42'
        Retrieves the certificate for request 42 directly.
    .EXAMPLE
        Get-PWSHCertreqCert -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -RequestID '42' `
            -OutputCertPath 'C:\certs\server01.cer'
        Retrieves the certificate and saves it to disk.
    .OUTPUTS
        PSCustomObject. Properties: Profile, CAServer, RequestID, Status, CertBase64,
        Certificate, RawOutput.
        Status is one of: Issued, Pending.
        Certificate (ASN.1-decoded PSCustomObject) is populated only when Status is Issued.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [object] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $CAFqdn,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $RequestID,

        [Parameter()]
        [string] $OutputCertPath,

        [Parameter()]
        [pscredential] $Credential
    )

    dynamicparam {
        New-ProfileDynamicParameter -ParameterSetName 'Direct'
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            $Profile   = $InputObject.Profile
            $CAFqdn    = $InputObject.CAServer
            $RequestID = $InputObject.RequestID
        } else {
            $Profile = $PSBoundParameters['Profile']
        }

        $config        = Read-ConfigFile
        $Profile       = Resolve-ProfileName -Config $config -ProfileName $Profile
        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $sessionArgs = @{ CAFqdn = $CAFqdn; RemotingConfig = $profileConfig.remoting }
        if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
        $session = Get-CASession @sessionArgs

        try {
            $result = Invoke-CertreqRetrieve -Session $session -RequestID $RequestID

            $certificate = $null
            if ($result.Status -eq 'Issued' -and $result.CertBase64) {
                $certificate = ConvertFrom-CertutilAsn1 -CertBase64 $result.CertBase64
                if ($PSBoundParameters.ContainsKey('OutputCertPath')) {
                    [IO.File]::WriteAllBytes($OutputCertPath, [Convert]::FromBase64String($result.CertBase64))
                    Write-Verbose "Certificate saved to $OutputCertPath"
                }
            }

            [PSCustomObject]@{
                Profile     = $Profile
                CAServer    = $CAFqdn
                RequestID   = $RequestID
                Status      = $result.Status
                CertBase64  = $result.CertBase64
                Certificate = $certificate
                RawOutput   = $result.RawOutput
            }
        } catch {
            Write-Error "Failed to retrieve certificate for RequestID $RequestID from '$CAFqdn': $_"
        }
    }
}
