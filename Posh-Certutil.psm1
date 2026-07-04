$script:SessionPool = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$script:ModuleRoot  = $PSScriptRoot
$script:ConfigPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Config\Posh-Certutil.json'

Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Filter '*.ps1' -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path "$PSScriptRoot\Public" -Filter '*.ps1' -ErrorAction Stop |
    ForEach-Object {
        . $_.FullName
        Export-ModuleMember -Function $_.BaseName
    }

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    $script:SessionPool.Values | ForEach-Object {
        if ($null -ne $_.Session) {
            Remove-PSSession -Session $_.Session -ErrorAction SilentlyContinue
        }
    }
    $script:SessionPool.Clear()
}
