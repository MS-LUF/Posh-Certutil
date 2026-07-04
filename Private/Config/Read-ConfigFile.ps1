function Read-ConfigFile {
    if (-not (Test-Path -Path $script:ConfigPath -PathType Leaf)) {
        return [PSCustomObject]@{
            version  = '1.0'
            profiles = [PSCustomObject]@{}
        }
    }
    $raw = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
    $raw | ConvertFrom-Json
}
