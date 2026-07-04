function Invoke-CertreqSubmit {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [byte[]]  $CSRBytes,
        [Parameter(Mandatory)] [string]  $CertificateTemplate
    )

    $sb = {
        param([byte[]]$CSRBytes, [string]$CertificateTemplate)

        $caName   = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' `
                        -Name 'Active').Active
        $tempCSR  = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$([IO.Path]::GetRandomFileName()).req")
        $tempCert = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$([IO.Path]::GetRandomFileName()).cer")

        try {
            [IO.File]::WriteAllBytes($tempCSR, $CSRBytes)

            $output   = & certreq.exe -config ".\$caName" -attrib "CertificateTemplate:$CertificateTemplate" `
                            -submit $tempCSR $tempCert 2>&1
            $exitCode = $LASTEXITCODE

            # Parse RequestID — certreq emits two lines: quoted and unquoted; take the unquoted one
            $requestId = $null
            foreach ($line in $output) {
                if ($line -match '^RequestId:\s*(\d+)$') { $requestId = $Matches[1]; break }
            }

            # Status: non-zero exit = failure; cert file written = issued; otherwise pending
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
                RequestID  = $requestId
                Status     = $status
                CertBase64 = $certBase64
                ExitCode   = $exitCode
                RawOutput  = $output -join "`n"
            }
        } finally {
            Remove-Item -Path $tempCSR  -ErrorAction SilentlyContinue
            Remove-Item -Path $tempCert -ErrorAction SilentlyContinue
        }
    }

    $result = Invoke-Command -Session $Session -ScriptBlock $sb `
                  -ArgumentList $CSRBytes, $CertificateTemplate -ErrorAction Stop

    if ($result.Status -eq 'Failed') {
        throw "certreq -submit failed (exit code $($result.ExitCode)): $($result.RawOutput)"
    }

    $result
}
