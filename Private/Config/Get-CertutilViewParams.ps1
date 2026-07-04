function Get-CertutilViewParams {
    param(
        [Parameter(Mandatory)] [object] $ProfileConfig,
        [Parameter(Mandatory)]
        [ValidateSet('issuedCerts', 'revokedCerts', 'expiringCerts', 'search')]
        [string] $Operation,
        [Parameter()] [hashtable] $Substitutions = @{}
    )

    $restrict = $ProfileConfig.certutilView.restrict.$Operation
    $out      = ($ProfileConfig.certutilView.out.$Operation) -join ','

    if (-not $restrict) { throw "No restrict value defined for operation '$Operation' in this profile." }
    if (-not $out)      { throw "No out value defined for operation '$Operation' in this profile." }

    foreach ($key in $Substitutions.Keys) {
        $restrict = $restrict -replace [regex]::Escape("{$key}"), $Substitutions[$key]
    }

    [PSCustomObject]@{
        Restrict = $restrict
        Out      = $out
    }
}
