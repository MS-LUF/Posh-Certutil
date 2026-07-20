function Submit-PWSHCertreqCSR {
    <#
    .SYNOPSIS
        Submits a certificate signing request (CSR) to a CA in a profile.
    .DESCRIPTION
        Connects to the specified CA via WinRM, transfers the local CSR file to the CA,
        and runs certreq -submit with the given certificate template. Returns the request
        status and, if the certificate is immediately issued, the ASN.1-decoded certificate.

        When the CA template requires manager approval the request enters Pending state.
        Use Approve-PWSHCertutilPendingCert (as a CA administrator) to issue the request,
        then use Get-PWSHCertreqCert to retrieve the issued certificate. The returned object
        carries Profile, CAServer, and RequestID so it can be piped directly into those cmdlets.
    .PARAMETER Profile
        The configuration profile to use. Optional; falls back to the profile marked as
        default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted. Throws if omitted
        and no default profile is configured.
    .PARAMETER CAFqdn
        The CA to submit the request to. Must be defined in the profile.
    .PARAMETER CSRPath
        Path to the certificate request file (.req, .csr, or .p10) on the local machine.
    .PARAMETER CertificateTemplate
        The LDAP name of the certificate template (not the display name).
    .PARAMETER OutputCertPath
        Optional. When the certificate is immediately issued, save the DER-encoded certificate
        to this local file path.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to the current user.
    .EXAMPLE
        Submit-PWSHCertreqCSR -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
            -CSRPath 'C:\requests\server01.req' -CertificateTemplate 'WebServer'
        Submits the CSR to ca01.corp.local using the WebServer template.
        Returns an object with Status='Issued' or Status='Pending'.
    .EXAMPLE
        Submit-PWSHCertreqCSR -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
            -CSRPath 'C:\requests\server01.req' -CertificateTemplate 'WebServer' `
            -OutputCertPath 'C:\certs\server01.cer'
        Submits the CSR and saves the issued certificate to disk if immediately approved.
    .EXAMPLE
        $pending = Submit-PWSHCertreqCSR -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
            -CSRPath 'C:\requests\server01.req' -CertificateTemplate 'ManualApproval'
        $pending | Approve-PWSHCertutilPendingCert -Confirm:$false
        $pending | Get-PWSHCertreqCert
        Full pending-approval workflow: submit, approve as CA manager, retrieve certificate.
    .OUTPUTS
        PSCustomObject. Properties: Profile, CAServer, RequestID, Status, CertificateTemplate,
        CertBase64, Certificate, RawOutput.
        Status is one of: Issued, Pending.
        Certificate (ASN.1-decoded PSCustomObject) is populated only when Status is Issued.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $CAFqdn,

        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not (Test-Path -Path $_ -PathType Leaf)) {
                throw "CSR file not found: '$_'"
            }
            $true
        })]
        [string] $CSRPath,

        [Parameter(Mandatory)]
        [string] $CertificateTemplate,

        [Parameter()]
        [string] $OutputCertPath,

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

        $found = $profileConfig.cas | Where-Object { $_.fqdn -eq $CAFqdn }
        if (-not $found) { throw "CA '$CAFqdn' is not defined in profile '$Profile'." }

        $csrBytes = [IO.File]::ReadAllBytes((Resolve-Path $CSRPath).Path)

        $sessionArgs = @{ CAFqdn = $CAFqdn; RemotingConfig = $profileConfig.remoting }
        if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
        $session = Get-CASession @sessionArgs

        try {
            $result = Invoke-CertreqSubmit -Session $session -CSRBytes $csrBytes `
                          -CertificateTemplate $CertificateTemplate

            $certificate = $null
            if ($result.Status -eq 'Issued' -and $result.CertBase64) {
                $certificate = ConvertFrom-CertutilAsn1 -CertBase64 $result.CertBase64
                if ($PSBoundParameters.ContainsKey('OutputCertPath')) {
                    [IO.File]::WriteAllBytes($OutputCertPath, [Convert]::FromBase64String($result.CertBase64))
                    Write-Verbose "Certificate saved to $OutputCertPath"
                }
            }

            [PSCustomObject]@{
                Profile             = $Profile
                CAServer            = $CAFqdn
                RequestID           = $result.RequestID
                Status              = $result.Status
                CertificateTemplate = $CertificateTemplate
                CertBase64          = $result.CertBase64
                Certificate         = $certificate
                RawOutput           = $result.RawOutput
            }
        } catch {
            Write-Error "Failed to submit CSR to '$CAFqdn': $_"
        }
    }
}
