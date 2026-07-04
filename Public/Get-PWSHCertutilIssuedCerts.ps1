function Get-PWSHCertutilIssuedCerts {
    <#
    .SYNOPSIS
        Gets issued certificates from one or all CAs in a profile.
    .DESCRIPTION
        Connects to each CA defined in the profile via WinRM, runs certutil -view filtered
        to issued certificates, and returns them as PowerShell objects. The restrict and out
        values are read dynamically from the profile configuration. Each object includes
        Profile and CAServer properties identifying its source.
    .PARAMETER Profile
        The configuration profile to use.
    .PARAMETER CAFqdn
        Optional. Queries only this CA instead of all CAs in the profile.
    .PARAMETER Credential
        Optional PSCredential for WinRM authentication. Defaults to current user.
    .EXAMPLE
        Get-PWSHCertutilIssuedCerts -Profile 'prod-pki'
        Retrieves all issued certificates from every CA in the 'prod-pki' profile.
    .EXAMPLE
        Get-PWSHCertutilIssuedCerts -Profile 'prod-pki' -CAFqdn 'ca01.corp.local'
        Retrieves issued certificates from ca01.corp.local only.
    .EXAMPLE
        Get-PWSHCertutilIssuedCerts -Profile 'prod-pki' | Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) }
        Finds issued certificates expiring within 30 days.
    .OUTPUTS
        PSCustomObject[]. One object per certificate with Profile, CAServer, and all configured -out fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Profile,

        [Parameter()]
        [string] $CAFqdn,

        [Parameter()]
        [pscredential] $Credential
    )

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

    $viewParams = Get-CertutilViewParams -ProfileConfig $profileConfig -Operation 'issuedCerts'

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
            $rawOutput = Invoke-CertutilView -Session $session -Restrict $viewParams.Restrict -Out $viewParams.Out
            ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap |
                Add-ResultMetadata -Profile $Profile -CAServer $ca.fqdn
        } catch {
            Write-Error "Failed to query issued certs from '$($ca.fqdn)': $_"
        }
    }
}
