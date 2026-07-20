function Revoke-PWSHCertutilIssuedCerts {
    <#
    .SYNOPSIS
        Revokes one or more certificates on the CA where they were issued.
    .DESCRIPTION
        Runs certutil -revoke on the CA identified by the piped object or by the explicit
        -Profile / -CAFqdn / -RequestID parameters. Accepts pipeline input from
        Get-PWSHCertutilIssuedCerts or Search-PWSHCertutilCerts so the CA does not need to
        be specified manually. Supports -WhatIf and -Confirm.
    .PARAMETER InputObject
        A certificate object with Profile, CAServer, and SerialNumber properties.
    .PARAMETER Profile
        The configuration profile. Optional in the Direct parameter set; falls back to the
        profile marked as default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted.
        Throws if omitted and no default profile is configured.
    .PARAMETER CAFqdn
        The CA where the certificate resides. Required in the Direct parameter set.
    .PARAMETER SerialNumber
        The serial number of the certificate to revoke. Required in the Direct parameter set.
    .PARAMETER Reason
        Revocation reason. Accepts named values (Unspecified, KeyCompromise, CACompromise,
        AffiliationChanged, Superseded, CessationOfOperation, CertificateHold) or
        the corresponding integer codes 0–6. Default: Unspecified.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Get-PWSHCertutilIssuedCerts -Profile 'prod-pki' | Where-Object CommonName -eq 'server01' | Revoke-PWSHCertutilIssuedCerts -Reason KeyCompromise
        Revokes the certificate for server01 due to key compromise.
    .EXAMPLE
        Revoke-PWSHCertutilIssuedCerts -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -SerialNumber '1A2B3C4D5E6F' -Reason Superseded -WhatIf
        Shows what would happen without performing the revocation.
    .OUTPUTS
        PSCustomObject. Profile, CAServer, SerialNumber, Reason, Success, and Output properties.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline', SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [object] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $CAFqdn,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $SerialNumber,

        [Parameter()]
        [ValidateSet('Unspecified','KeyCompromise','CACompromise','AffiliationChanged',
                     'Superseded','CessationOfOperation','CertificateHold',
                     '0','1','2','3','4','5','6')]
        [string] $Reason = 'Unspecified',

        [Parameter()]
        [pscredential] $Credential
    )

    dynamicparam {
        New-ProfileDynamicParameter -ParameterSetName 'Direct'
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            $Profile      = $InputObject.Profile
            $CAFqdn       = $InputObject.CAServer
            $SerialNumber = $InputObject.SerialNumber
        } else {
            $Profile = $PSBoundParameters['Profile']
        }

        $config  = Read-ConfigFile
        $Profile = Resolve-ProfileName -Config $config -ProfileName $Profile

        $target = "SerialNumber=$SerialNumber on $CAFqdn (Profile: $Profile, Reason: $Reason)"
        if (-not $PSCmdlet.ShouldProcess($target, 'Revoke certificate')) { return }

        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $sessionArgs = @{ CAFqdn = $CAFqdn; RemotingConfig = $profileConfig.remoting }
        if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
        $session = Get-CASession @sessionArgs

        try {
            $output  = Invoke-CertutilRevoke -Session $session -SerialNumber $SerialNumber -Reason $Reason
            $success = $output -notmatch 'FAILED'
            [PSCustomObject]@{
                Profile      = $Profile
                CAServer     = $CAFqdn
                SerialNumber = $SerialNumber
                Reason       = $Reason
                Success      = $success
                Output       = $output -join "`n"
            }
        } catch {
            Write-Error "Failed to revoke SerialNumber $SerialNumber on $CAFqdn : $_"
        }
    }
}
