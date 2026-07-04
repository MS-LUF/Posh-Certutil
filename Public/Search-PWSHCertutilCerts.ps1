function Search-PWSHCertutilCerts {
    <#
    .SYNOPSIS
        Searches for issued and/or revoked certificates across all CAs in a profile.
    .DESCRIPTION
        Builds a dynamic certutil -restrict string from the supplied filter parameters and
        queries every CA in the profile. Multiple values for the same parameter are combined
        with OR logic. Results include Profile and CAServer metadata. The out columns come
        from the profile's certutilView.out.search configuration, read at call time.
    .PARAMETER Profile
        The configuration profile to use.
    .PARAMETER Type
        Which certificates to search: Issued, Revoked, or All. Default: All.
    .PARAMETER Requester
        One or more requester names to match (OR). Certutil wildcards supported.
    .PARAMETER Subject
        One or more CommonName values to match (OR).
    .PARAMETER Template
        One or more certificate template names to match (OR).
    .PARAMETER NotBefore
        Return only certificates issued on or after this date.
    .PARAMETER NotAfter
        Return only certificates expiring on or before this date.
    .PARAMETER SerialNumber
        One or more serial numbers to match (OR).
    .PARAMETER CAFqdn
        Optional. Queries only this CA instead of all CAs in the profile.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Search-PWSHCertutilCerts -Profile 'prod-pki' -Subject 'server01.corp.local'
        Finds all (issued + revoked) certificates for subject server01.corp.local.
    .EXAMPLE
        Search-PWSHCertutilCerts -Profile 'prod-pki' -Type Issued -Template 'WebServer','Workstation'
        Finds issued certificates using the WebServer or Workstation template.
    .EXAMPLE
        Search-PWSHCertutilCerts -Profile 'prod-pki' -Type Issued -NotAfter (Get-Date).AddDays(60)
        Finds issued certificates expiring within 60 days.
    .OUTPUTS
        PSCustomObject[]. One object per matching certificate with Profile, CAServer, and all configured search -out fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Profile,

        [Parameter()]
        [ValidateSet('Issued', 'Revoked', 'All')]
        [string] $Type = 'All',

        [Parameter()]
        [string[]] $Requester,

        [Parameter()]
        [string[]] $Subject,

        [Parameter()]
        [string[]] $Template,

        [Parameter()]
        [datetime] $NotBefore,

        [Parameter()]
        [datetime] $NotAfter,

        [Parameter()]
        [string[]] $SerialNumber,

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

    $parts = [System.Collections.Generic.List[string]]::new()
    switch ($Type) {
        'Issued'  { $parts.Add('Disposition=20') }
        'Revoked' { $parts.Add('Disposition=21') }
    }
    if ($Requester)    { $parts.Add(($Requester    | ForEach-Object { "RequesterName=$_"       }) -join '|') }
    if ($Subject)      { $parts.Add(($Subject       | ForEach-Object { "CommonName=$_"          }) -join '|') }
    if ($Template)     { $parts.Add(($Template      | ForEach-Object { "CertificateTemplate=$_" }) -join '|') }
    if ($SerialNumber) { $parts.Add(($SerialNumber  | ForEach-Object { "SerialNumber=$_"        }) -join '|') }
    if ($PSBoundParameters.ContainsKey('NotBefore')) {
        $parts.Add("NotBefore>=$($NotBefore.ToString('MM\/dd\/yyyy'))")
    }
    if ($PSBoundParameters.ContainsKey('NotAfter')) {
        $parts.Add("NotAfter<=$($NotAfter.ToString('MM\/dd\/yyyy'))")
    }

    $restrict = if ($parts.Count -gt 0) { $parts -join ',' } else { 'GeneralFlags=0' }
    $out      = ($profileConfig.certutilView.out.search) -join ','

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
            $rawOutput = Invoke-CertutilView -Session $session -Restrict $restrict -Out $out
            ConvertFrom-CertutilCsv -RawOutput $rawOutput -FieldMap $fieldMap |
                Add-ResultMetadata -Profile $Profile -CAServer $ca.fqdn
        } catch {
            Write-Error "Failed to search certs on '$($ca.fqdn)': $_"
        }
    }
}
