function Invoke-CertutilSchema {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session
    )

    $sb = {
        & certutil.exe -schema 2>$null
    }
    $output   = Invoke-Command -Session $Session -ScriptBlock $sb -ErrorAction Stop
    $failLine = $output | Where-Object { $_ -match 'CertUtil:.*command FAILED' }
    if ($failLine) {
        throw "certutil -schema failed: $($failLine -join ' ')"
    }
    $output
}
