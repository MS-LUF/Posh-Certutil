function Get-PWSHCertutilShortTermExpiringCerts {
    <#
    .SYNOPSIS
        Gets certificates expiring within a specified number of days from one or all CAs in a profile.
    .DESCRIPTION
        Connects to each CA in the profile via WinRM and retrieves issued certificates whose
        NotAfter date falls within the next N days. The expiration threshold is substituted
        dynamically into the profile's restrict template at query time, so changing -Days
        produces a different restrict without touching the config.
    .PARAMETER Profile
        The configuration profile to use.
    .PARAMETER Days
        Expiration window in days. Accepted values: 30, 60, 90, 120. Default: 30.
    .PARAMETER CAFqdn
        Optional. Queries only this CA instead of all CAs in the profile.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Get-PWSHCertutilShortTermExpiringCerts -Profile 'prod-pki'
        Returns certificates expiring within 30 days from all CAs in 'prod-pki'.
    .EXAMPLE
        Get-PWSHCertutilShortTermExpiringCerts -Profile 'prod-pki' -Days 90
        Returns certificates expiring within 90 days.
    .OUTPUTS
        PSCustomObject[]. One object per expiring certificate with Profile, CAServer, and all configured -out fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Profile,

        [Parameter()]
        [ValidateSet(30, 60, 90, 120)]
        [int] $Days = 30,

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

    $cas = if ($PSBoundParameters.ContainsKey('CAFqdn')) {
        $found = $profileConfig.cas | Where-Object { $_.fqdn -eq $CAFqdn }
        if (-not $found) { throw "CA '$CAFqdn' is not defined in profile '$Profile'." }
        $found
    } else { $profileConfig.cas }

    foreach ($ca in $cas) {
        try {
            $sessionArgs = @{ CAFqdn = $ca.fqdn; RemotingConfig = $profileConfig.remoting }
            if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }

            $session    = Get-CASession @sessionArgs
            # Compute dates on the CA server so the format and timezone match what certutil expects.
            $caDate     = Get-CALocalDate -Session $session -Days $Days
            $viewParams = Get-CertutilViewParams -ProfileConfig $profileConfig -Operation 'expiringCerts' `
                              -Substitutions @{ TODAY = $caDate.Today; EXPIRE_DATE = $caDate.ExpireDate }
            $rawOutput  = Invoke-CertutilView -Session $session -Restrict $viewParams.Restrict -Out $viewParams.Out
            ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap |
                Add-ResultMetadata -Profile $Profile -CAServer $ca.fqdn
        } catch {
            Write-Error "Failed to query expiring certs from '$($ca.fqdn)': $_"
        }
    }
}
