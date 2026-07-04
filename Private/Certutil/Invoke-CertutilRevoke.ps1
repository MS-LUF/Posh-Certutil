function Invoke-CertutilRevoke {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $SerialNumber,
        [Parameter(Mandatory)] [string] $Reason
    )

    $reasonMap = @{
        'Unspecified'          = 0
        'KeyCompromise'        = 1
        'CACompromise'         = 2
        'AffiliationChanged'   = 3
        'Superseded'           = 4
        'CessationOfOperation' = 5
        'CertificateHold'      = 6
    }

    $reasonCode = if ($Reason -match '^\d+$') {
        [int]$Reason
    } elseif ($reasonMap.ContainsKey($Reason)) {
        $reasonMap[$Reason]
    } else {
        throw "Invalid revocation reason '$Reason'. Valid values: $($reasonMap.Keys -join ', ') or an integer 0-6."
    }

    $sb = {
        param($SerialNumber, $ReasonCode)
        & certutil.exe -revoke $SerialNumber $ReasonCode 2>&1
    }

    $output = Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $SerialNumber, $reasonCode -ErrorAction Stop

    if ($output -match 'CertUtil: -revoke command FAILED') {
        throw "certutil -revoke failed for SerialNumber $SerialNumber : $($output -join ' ')"
    }
    $output
}
