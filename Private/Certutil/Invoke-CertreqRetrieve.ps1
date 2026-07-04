function Invoke-CertreqRetrieve {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $RequestID
    )

    $sb = {
        param([string]$RequestID)

        $caName   = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' `
                        -Name 'Active').Active
        $tempCert = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$([IO.Path]::GetRandomFileName()).cer")

        try {
            $output   = & certreq.exe -config ".\$caName" -retrieve $RequestID $tempCert 2>&1
            $exitCode = $LASTEXITCODE

            $certBase64 = $null
            $status = if ($exitCode -ne 0) {
                'Failed'
            } elseif (Test-Path $tempCert) {
                $certBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tempCert))
                'Issued'
            } else {
                'Pending'
            }

            [PSCustomObject]@{
                RequestID  = $RequestID
                Status     = $status
                CertBase64 = $certBase64
                ExitCode   = $exitCode
                RawOutput  = $output -join "`n"
            }
        } finally {
            Remove-Item -Path $tempCert -ErrorAction SilentlyContinue
        }
    }

    $result = Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $RequestID -ErrorAction Stop

    if ($result.Status -eq 'Failed') {
        throw "certreq -retrieve failed for RequestID $RequestID (exit code $($result.ExitCode)): $($result.RawOutput)"
    }

    $result
}
