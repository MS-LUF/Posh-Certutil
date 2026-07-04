function ConvertFrom-CertutilSchema {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]] $RawOutput
    )

    # Column data lines start with a word-character token followed by 2+ spaces.
    # This pattern reliably excludes headers, separators, section titles, and status lines.
    foreach ($line in $RawOutput) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\w\S+\s{2,}') {
            $name = ($trimmed -split '\s{2,}', 2)[0].Trim()
            if ($name) { $name }
        }
    }
}
