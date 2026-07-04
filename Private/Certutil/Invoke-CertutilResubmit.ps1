function Invoke-CertutilResubmit {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $RequestID
    )

    $sb = {
        param([string]$RequestID)
        & certutil.exe -resubmit $RequestID 2>&1
    }

    $output = Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $RequestID -ErrorAction Stop

    if ($output -match 'CertUtil:.*command FAILED') {
        throw "certutil -resubmit failed for RequestID $RequestID : $($output -join ' ')"
    }

    $output
}
