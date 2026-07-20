function ConvertTo-ProfileSyncStateDateTime {
    param(
        [Parameter(Mandatory)] [object] $ProfileConfig
    )

    # syncState.lastSync is always written by this module itself (Invoke-ProfileAutoSync /
    # Sync-PWSHCertutilCASchema) via [datetime]::UtcNow.ToString('o') — the round-trip ('o')
    # format is culture-invariant, so no CA-locale awareness is needed to parse it back.
    if ($ProfileConfig.syncState -and $ProfileConfig.syncState.lastSync) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse(
                $ProfileConfig.syncState.lastSync,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind,
                [ref] $parsed)) {
            $ProfileConfig.syncState.lastSync = $parsed
        }
    }
    $ProfileConfig
}
