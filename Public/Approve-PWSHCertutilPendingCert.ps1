function Approve-PWSHCertutilPendingCert {
    <#
    .SYNOPSIS
        Issues (approves) a pending certificate request on a CA.
    .DESCRIPTION
        Connects to the specified CA via WinRM and runs certutil -resubmit to issue a
        pending certificate request. This is the CA administrator action that moves a
        request from Pending to Issued state.

        Accepts pipeline input from Submit-PWSHCertreqCSR where Status is Pending, so the
        submit-approve-retrieve workflow can be written as a pipeline. Supports -WhatIf and
        -Confirm.

        After approval, use Get-PWSHCertreqCert to retrieve the issued certificate.
    .PARAMETER InputObject
        A request object with Profile, CAServer, and RequestID properties.
        Accepts output from Submit-PWSHCertreqCSR.
    .PARAMETER Profile
        The configuration profile. Optional in the Direct parameter set; falls back to the
        profile marked as default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted.
        Throws if omitted and no default profile is configured.
    .PARAMETER CAFqdn
        The CA where the request is pending. Required in the Direct parameter set.
    .PARAMETER RequestID
        The request ID to approve. Required in the Direct parameter set.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to the current user.
    .EXAMPLE
        $pending | Approve-PWSHCertutilPendingCert -Confirm:$false
        Approves a pending request returned by Submit-PWSHCertreqCSR.
    .EXAMPLE
        Approve-PWSHCertutilPendingCert -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
            -RequestID '42'
        Approves request 42 on ca01.corp.local.
    .EXAMPLE
        Approve-PWSHCertutilPendingCert -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
            -RequestID '42' -WhatIf
        Shows what would be approved without performing the action.
    .OUTPUTS
        PSCustomObject. Properties: Profile, CAServer, RequestID, Success, Output.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [object] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $CAFqdn,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $RequestID,

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

        $config  = Read-ConfigFile
        $Profile = Resolve-ProfileName -Config $config -ProfileName $Profile

        $target = "RequestID=$RequestID on $CAFqdn (Profile: $Profile)"
        if (-not $PSCmdlet.ShouldProcess($target, 'Approve pending certificate request')) { return }

        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $sessionArgs = @{ CAFqdn = $CAFqdn; RemotingConfig = $profileConfig.remoting }
        if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
        $session = Get-CASession @sessionArgs

        try {
            $output  = Invoke-CertutilResubmit -Session $session -RequestID $RequestID
            $success = $output -notmatch 'FAILED'
            [PSCustomObject]@{
                Profile   = $Profile
                CAServer  = $CAFqdn
                RequestID = $RequestID
                Success   = $success
                Output    = $output -join "`n"
            }
        } catch {
            Write-Error "Failed to approve RequestID $RequestID on '$CAFqdn': $_"
        }
    }
}
