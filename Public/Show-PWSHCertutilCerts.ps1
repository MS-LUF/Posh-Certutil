function Show-PWSHCertutilCerts {
    <#
    .SYNOPSIS
        Decodes and returns ASN.1 certificate content as a structured PowerShell object.
    .DESCRIPTION
        Retrieves the binary certificate from the CA database via certutil and decodes it
        using the .NET X509Certificate2 class. Accepts a piped certificate object from
        Get-PWSHCertutilIssuedCerts, Get-PWSHCertutilRevokedCerts, or Search-PWSHCertutilCerts
        (Pipeline parameter set), or explicit -Profile / -CAFqdn / -RequestID (Direct parameter set).
    .PARAMETER InputObject
        A certificate object with Profile, CAServer, and RequestID properties.
    .PARAMETER Profile
        The configuration profile. Required in the Direct parameter set.
    .PARAMETER CAFqdn
        The CA FQDN where the certificate resides. Required in the Direct parameter set.
    .PARAMETER RequestID
        The certificate request ID. Required in the Direct parameter set.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Get-PWSHCertutilIssuedCerts -Profile 'prod-pki' | Where-Object CommonName -eq 'server01' | Show-PWSHCertutilCerts
        Decodes the certificate for server01 from the pipeline.
    .EXAMPLE
        Show-PWSHCertutilCerts -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -RequestID 42
        Decodes and displays certificate with request ID 42.
    .OUTPUTS
        PSCustomObject. Decoded ASN.1 fields (Subject, Issuer, NotBefore, NotAfter, Extensions, etc.)
        plus Profile and CAServer properties.
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
            & certutil.exe -view -restrict "RequestID=$ReqID" -out 'BinaryCertificate' csv 2>$null
        }
        $rawOutput = Invoke-Command -Session $session -ScriptBlock $sb -ArgumentList $RequestID -ErrorAction Stop
        $csvData   = ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap

        if (-not $csvData) {
            Write-Error "No certificate found with RequestID $RequestID on $CAFqdn"
            return
        }

        # BinaryCertificate in certutil CSV output is DER bytes encoded as base64
        $certRaw = $csvData.BinaryCertificate -replace '\s', ''
        $decoded = ConvertFrom-CertutilAsn1 -CertBase64 $certRaw
        $decoded | Add-ResultMetadata -Profile $Profile -CAServer $CAFqdn
    }
}
