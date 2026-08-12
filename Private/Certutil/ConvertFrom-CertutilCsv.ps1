function ConvertFrom-CertutilCsv {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]] $RawOutput,
        [Parameter()] [hashtable] $FieldMap = @{},
        [Parameter()] [string] $CACulture
    )

    # Canonical (post-FieldMap-rename) column names that hold certutil date/time values.
    $dateFieldNames = @('NotBefore', 'NotAfter', 'RevokedEffectiveWhen')

    # Both the CSV header and data rows start with a double-quote.
    # certutil status/count lines do not — this filter handles both.
    $csvLines = $RawOutput | Where-Object { $_ -match '^"' }

    if (($csvLines | Measure-Object).Count -le 1) { return @() }

    $objects = $csvLines | ConvertFrom-Csv

    $renamed = if ($FieldMap.Count -eq 0) {
        $objects
    } else {
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

    # certutil's CertificateTemplate column is "<OID> <DisplayName>" for V2/V3 templates
    # (the display name may itself contain spaces) or just the plain name for legacy V1
    # templates (no OID). Split into two properties whenever the column is present, in
    # addition to the original combined value.
    $renamed = $renamed | ForEach-Object {
        $obj = $_
        if ($obj.PSObject.Properties.Name -contains 'CertificateTemplate') {
            $rawValue = $obj.CertificateTemplate
            if ($rawValue -match '^(?<oid>\d+(?:\.\d+){4,})\s+(?<name>.+)$') {
                $oid  = $Matches.oid
                $name = $Matches.name
            } else {
                $oid  = $null
                $name = if ([string]::IsNullOrWhiteSpace($rawValue)) { $null } else { $rawValue }
            }
            $obj |
                Add-Member -MemberType NoteProperty -Name 'CertificateTemplateOID' -Value $oid -Force -PassThru |
                Add-Member -MemberType NoteProperty -Name 'CertificateTemplateDisplayName' -Value $name -Force -PassThru
        } else {
            $obj
        }
    }

    if (-not $CACulture) { return $renamed }

    # certutil writes date/time columns in the CA server's own locale — parse using that
    # culture (not the admin machine's) so the resulting DateTime values are correct.
    $cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($CACulture)
    $renamed | ForEach-Object {
        $obj = $_
        foreach ($fieldName in $dateFieldNames) {
            if ($obj.PSObject.Properties.Name -notcontains $fieldName) { continue }
            $rawValue = $obj.$fieldName
            if ([string]::IsNullOrWhiteSpace($rawValue)) {
                $obj.$fieldName = $null
                continue
            }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($rawValue, $cultureInfo, [System.Globalization.DateTimeStyles]::None, [ref] $parsed)) {
                $obj.$fieldName = $parsed
            } else {
                Write-Warning "Could not parse '$fieldName' value '$rawValue' as a date using culture '$CACulture'; leaving as string."
            }
        }
        $obj
    }
}
