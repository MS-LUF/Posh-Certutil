function Remove-CASession {
    param(
        [Parameter(Mandatory)] [string] $CAFqdn,
        [Parameter(Mandatory)] [int]    $Port
    )

    $poolKey = "${CAFqdn}:${Port}"
    $entry   = $null
    if ($script:SessionPool.TryRemove($poolKey, [ref]$entry)) {
        Remove-PSSession -Session $entry.Session -ErrorAction SilentlyContinue
        Write-Verbose "Removed WinRM session for $CAFqdn"
    }
}
