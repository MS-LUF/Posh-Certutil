function Get-CertutilFieldNameMap {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string[]] $CanonicalFieldNames
    )

    $out = $CanonicalFieldNames -join ','

    $sb = {
        param([string]$Out)
        & certutil.exe -view -restrict 'RequestID=0' -out $Out csv 2>$null
    }

    $rawOutput = Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $out -ErrorAction Stop

    # First quoted line is the CSV header with localized column names
    $headerLine = $rawOutput | Where-Object { $_ -match '^"' } | Select-Object -First 1

    if (-not $headerLine) {
        throw "Get-CertutilFieldNameMap: no CSV header returned from CA. Cannot build field name map."
    }

    # Add a dummy data row so ConvertFrom-Csv treats the first line as column headers
    $dummyRow       = ($CanonicalFieldNames | ForEach-Object { '""' }) -join ','
    $parsed         = @($headerLine, $dummyRow) | ConvertFrom-Csv
    $localizedNames = @($parsed.PSObject.Properties.Name)

    if ($localizedNames.Count -ne $CanonicalFieldNames.Count) {
        throw "Get-CertutilFieldNameMap: expected $($CanonicalFieldNames.Count) columns but CA returned $($localizedNames.Count). Cannot build field name map."
    }

    $map = @{}
    for ($i = 0; $i -lt $CanonicalFieldNames.Count; $i++) {
        $map[$localizedNames[$i]] = $CanonicalFieldNames[$i]
    }
    $map
}
