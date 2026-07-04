function Get-CASession {
    param(
        [Parameter(Mandatory)] [string]      $CAFqdn,
        [Parameter(Mandatory)] [object]      $RemotingConfig,
        [Parameter()]          [pscredential] $Credential
    )

    $port        = [int]$RemotingConfig.port
    $useTls      = [bool]$RemotingConfig.useTls
    $maxSessions = [int]$RemotingConfig.maxSessionsPerCA
    $poolKey     = "${CAFqdn}:${port}"

    # Return existing live session
    $entry = $null
    if ($script:SessionPool.TryGetValue($poolKey, [ref]$entry)) {
        if (Test-CASession -Session $entry.Session) {
            $entry.LastUsed = [datetime]::UtcNow
            return $entry.Session
        }
        # Evict dead session
        $script:SessionPool.TryRemove($poolKey, [ref]$null) | Out-Null
        Remove-PSSession -Session $entry.Session -ErrorAction SilentlyContinue
    }

    # Respect maxSessionsPerCA — wait up to 30 s for a slot
    $deadline = [datetime]::UtcNow.AddSeconds(30)
    while (($script:SessionPool.Keys | Where-Object { $_ -like "${CAFqdn}:*" } | Measure-Object).Count -ge $maxSessions) {
        if ([datetime]::UtcNow -gt $deadline) {
            throw "Timed out waiting for a session slot for CA '$CAFqdn' (max $maxSessions sessions)."
        }
        Start-Sleep -Milliseconds 500
    }

    $sessionParams = @{
        ComputerName = $CAFqdn
        Port         = $port
        ErrorAction  = 'Stop'
    }
    if ($useTls)    { $sessionParams['UseSSL']     = $true }
    if ($Credential){ $sessionParams['Credential'] = $Credential }

    Write-Verbose "Opening new WinRM session to $CAFqdn (port $port, TLS=$useTls)"
    $session = New-PSSession @sessionParams

    $script:SessionPool[$poolKey] = [PSCustomObject]@{
        Session  = $session
        CAFqdn   = $CAFqdn
        LastUsed = [datetime]::UtcNow
    }
    $session
}
