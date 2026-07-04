function Get-PWSHCertutilCertStatus {
    <#
    .SYNOPSIS
        Gets the current status (Issued or Revoked) of a certificate, with CRL information.
    .DESCRIPTION
        Retrieves disposition and revocation details for a certificate from the CA database
        and returns a structured object with the status, CRL information, and the decoded
        ASN.1 certificate. Accepts piped objects from the Get-* and Search-PWSHCertutil*
        cmdlets, or explicit -Profile / -CAFqdn / -RequestID parameters.
    .PARAMETER InputObject
        A certificate object with Profile, CAServer, and RequestID properties.
    .PARAMETER Profile
        The configuration profile. Required in the Direct parameter set.
    .PARAMETER CAFqdn
        The CA FQDN. Required in the Direct parameter set.
    .PARAMETER RequestID
        The certificate request ID. Required in the Direct parameter set.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Search-PWSHCertutilCerts -Profile 'prod-pki' -Subject 'server01' | Get-PWSHCertutilCertStatus
        Returns the current status of all certificates matching 'server01'.
    .EXAMPLE
        Get-PWSHCertutilCertStatus -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -RequestID 42
        Returns the status of certificate request ID 42.
    .OUTPUTS
        PSCustomObject. Profile, CAServer, RequestID, Status, CRLInfo, and Certificate (decoded ASN.1) properties.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [object] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $Profile,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $CAFqdn,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [string] $RequestID,

        [Parameter()]
        [pscredential] $Credential
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            $Profile   = $InputObject.Profile
            $CAFqdn    = $InputObject.CAServer
            $RequestID = $InputObject.RequestID
        }

        $config        = Read-ConfigFile
        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $autoSyncArgs = @{ Config = $config; ProfileName = $Profile; ProfileConfig = $profileConfig }
        if ($PSBoundParameters.ContainsKey('Credential')) { $autoSyncArgs['Credential'] = $Credential }
        $profileConfig = Invoke-ProfileAutoSync @autoSyncArgs

        $fieldMap = @{}
        if ($profileConfig.syncState -and $profileConfig.syncState.fieldNameMap) {
            $profileConfig.syncState.fieldNameMap.PSObject.Properties |
                ForEach-Object { $fieldMap[$_.Name] = $_.Value }
        }

        $sessionArgs = @{ CAFqdn = $CAFqdn; RemotingConfig = $profileConfig.remoting }
        if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
        $session = Get-CASession @sessionArgs

        $sb = {
            param($ReqID)
            $restrict = "RequestID=$ReqID"
            $out      = 'RequestID,Disposition,RequesterName,CommonName,NotBefore,NotAfter,SerialNumber,BinaryCertificate,RevokedReason,RevokedEffectiveWhen'
            & certutil.exe -view -restrict $restrict -out $out csv 2>$null
        }
        $rawOutput = Invoke-Command -Session $session -ScriptBlock $sb -ArgumentList $RequestID -ErrorAction Stop
        $csvData   = ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap

        if (-not $csvData) {
            Write-Error "No certificate found with RequestID $RequestID on $CAFqdn"
            return
        }

        $row    = $csvData | Select-Object -First 1
        $status = switch ($row.Disposition) {
            '20'    { 'Issued' }
            '21'    { 'Revoked' }
            default { "Unknown ($($row.Disposition))" }
        }

        $certDecoded = $null
        if ($row.BinaryCertificate) {
            $certDecoded = ConvertFrom-CertutilAsn1 -CertBase64 ($row.BinaryCertificate -replace '\s', '')
        }

        [PSCustomObject]@{
            Profile     = $Profile
            CAServer    = $CAFqdn
            RequestID   = $row.RequestID
            Status      = $status
            CRLInfo     = [PSCustomObject]@{
                RevokedReason = $row.RevokedReason
                RevokedWhen   = $row.RevokedEffectiveWhen
            }
            Certificate = $certDecoded
        }
    }
}
