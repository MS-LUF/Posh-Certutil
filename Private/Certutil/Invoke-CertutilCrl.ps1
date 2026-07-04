function Invoke-CertutilCrl {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session
    )

    $sb = {
        $publishOutput = & certutil.exe -crl 2>&1

        if ($publishOutput -match 'CertUtil:.*command FAILED') {
            throw "certutil -crl failed: $($publishOutput -join ' ')"
        }

        $certEnroll = Join-Path -Path $env:SystemRoot -ChildPath 'System32\CertSrv\CertEnroll'
        $crlFile    = Get-ChildItem -Path $certEnroll -Filter '*.crl' |
                          Sort-Object LastWriteTime -Descending |
                          Select-Object -First 1

        if (-not $crlFile) {
            throw "No CRL file found in $certEnroll after certutil -crl."
        }

        [PSCustomObject]@{
            PublishOutput = $publishOutput -join "`n"
            FileName      = $crlFile.Name
            LastWriteTime = $crlFile.LastWriteTime
            CrlBase64     = [Convert]::ToBase64String([IO.File]::ReadAllBytes($crlFile.FullName))
        }
    }

    Invoke-Command -Session $Session -ScriptBlock $sb -ErrorAction Stop
}
