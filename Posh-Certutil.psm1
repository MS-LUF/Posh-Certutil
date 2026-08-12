$script:SessionPool = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$script:ModuleRoot  = $PSScriptRoot
$script:ConfigPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Config\Posh-Certutil.json'

# Logging severity order, used by Write-PWSHCertutilLog to compare a log entry's Level
# against the configured MinimumLevel. Debug also doubles as the EventLog entry
# type/EventId for Debug-level entries, since Windows Event Log has no Debug type.
$script:LogLevelSeverity   = @{ Debug = 0; Information = 1; Warning = 2; Error = 3 }
# "Warn once per session" flags so a misconfigured or unreachable logging destination
# doesn't spam Write-Warning on every single log call inside a per-CA loop.
$script:LoggingConfigWarned = $false
$script:LoggingSinkFailed   = $false

# Singular-noun aliases for cmdlets whose noun predates the PowerShell approved-verb/noun
# guideline requiring singular nouns. The plural name stays the canonical, exported function.
$script:CmdletAliases = @{
    'Get-PWSHCertutilIssuedCerts'            = 'Get-PWSHCertutilIssuedCert'
    'Get-PWSHCertutilRevokedCerts'           = 'Get-PWSHCertutilRevokedCert'
    'Get-PWSHCertutilShortTermExpiringCerts' = 'Get-PWSHCertutilShortTermExpiringCert'
    'Revoke-PWSHCertutilIssuedCerts'         = 'Revoke-PWSHCertutilIssuedCert'
    'Search-PWSHCertutilCerts'               = 'Search-PWSHCertutilCert'
    'Show-PWSHCertutilCerts'                 = 'Show-PWSHCertutilCert'
}

Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Filter '*.ps1' -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path "$PSScriptRoot\Public" -Filter '*.ps1' -ErrorAction Stop |
    ForEach-Object {
        . $_.FullName
        Export-ModuleMember -Function $_.BaseName

        if ($script:CmdletAliases.ContainsKey($_.BaseName)) {
            $aliasName = $script:CmdletAliases[$_.BaseName]
            New-Alias -Name $aliasName -Value $_.BaseName -Force
            Export-ModuleMember -Alias $aliasName
        }
    }

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    $script:SessionPool.Values | ForEach-Object {
        if ($null -ne $_.Session) {
            Remove-PSSession -Session $_.Session -ErrorAction SilentlyContinue
        }
    }
    $script:SessionPool.Clear()
}
