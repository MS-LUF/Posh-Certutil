function ConvertFrom-CertutilCsv {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]] $RawOutput,
        [Parameter()] [hashtable] $FieldMap = @{}
    )

    # Both the CSV header and data rows start with a double-quote.
    # certutil status/count lines do not — this filter handles both.
    $csvLines = $RawOutput | Where-Object { $_ -match '^"' }

    if (($csvLines | Measure-Object).Count -le 1) { return @() }

    $objects = $csvLines | ConvertFrom-Csv

    if ($FieldMap.Count -eq 0) { return $objects }

    # Rename localized CSV column names to canonical internal names
    $objects | ForEach-Object {
        $src     = $_
        $newHash = [ordered]@{}
        foreach ($prop in $src.PSObject.Properties) {
            $key = if ($FieldMap.ContainsKey($prop.Name)) { $FieldMap[$prop.Name] } else { $prop.Name }
            $newHash[$key] = $prop.Value
        }
        [PSCustomObject]$newHash
    }
}
