function Invoke-CertutilView {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $Restrict,
        [Parameter(Mandatory)] [string] $Out
    )

    $sb = {
        param($Restrict, $Out)
        & certutil.exe -view -restrict $Restrict -out $Out csv 2>$null
    }

    $output   = Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $Restrict, $Out -ErrorAction Stop
    $failLine = $output | Where-Object { $_ -match 'CertUtil:.*command FAILED' }
    if ($failLine) {
        throw "certutil -view failed: $($failLine -join ' ')"
    }
    $output
}
