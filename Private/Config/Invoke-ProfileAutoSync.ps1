function Invoke-ProfileAutoSync {
    param(
        [Parameter(Mandatory)] [object]        $Config,
        [Parameter(Mandatory)] [string]        $ProfileName,
        [Parameter(Mandatory)] [object]        $ProfileConfig,
        [Parameter()]          [pscredential]  $Credential
    )

    # If the profile has already been synced, return immediately
    if ($ProfileConfig.syncState -and $ProfileConfig.syncState.lastSync) {
        return $ProfileConfig
    }

    $firstCA = $ProfileConfig.cas[0].fqdn
    Write-Warning "Profile '$ProfileName' has no field name map. Running automatic schema sync against '$firstCA'..."

    # Collect all unique canonical field names configured in this profile's out arrays.
    # Only probe with fields the user has configured — they are guaranteed to exist on the CA.
    # Adding fields not in the profile's out arrays risks certutil FAILED output on CAs that
    # don't expose those columns, which would prevent any CSV header from being returned.
    $ops       = @('issuedCerts', 'revokedCerts', 'expiringCerts', 'search')
    $canonical = [System.Collections.Generic.List[string]]::new()
    foreach ($op in $ops) {
        $fields = $ProfileConfig.certutilView.out.$op
        if ($fields) {
            foreach ($f in $fields) {
                if (-not $canonical.Contains($f)) { $canonical.Add($f) }
            }
        }
    }

    try {
        $sessionArgs = @{ CAFqdn = $firstCA; RemotingConfig = $ProfileConfig.remoting }
        if ($Credential) { $sessionArgs['Credential'] = $Credential }
        $session  = Get-CASession @sessionArgs

        $fieldMap  = Get-CertutilFieldNameMap -Session $session -CanonicalFieldNames $canonical.ToArray()
        $syncState = [PSCustomObject]@{
            lastSync     = [datetime]::UtcNow.ToString('o')
            fieldNameMap = [PSCustomObject]$fieldMap
        }

        # $ProfileConfig is a reference inside $Config — Add-Member mutates both
        $ProfileConfig | Add-Member -MemberType NoteProperty -Name 'syncState' -Value $syncState -Force
        $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigPath -Encoding UTF8

        Write-Verbose "Auto-sync complete for profile '$ProfileName'. Field map saved to $script:ConfigPath"
    } catch {
        Write-Warning "Auto-sync failed for profile '$ProfileName': $_. Column names may be localized; pipeline chaining may not work correctly."
    }

    $ProfileConfig
}
