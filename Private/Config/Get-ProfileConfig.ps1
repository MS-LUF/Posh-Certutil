function Get-ProfileConfig {
    param(
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] [string] $ProfileName
    )

    $available = $Config.profiles.PSObject.Properties.Name
    if ($ProfileName -notin $available) {
        throw "Profile '$ProfileName' not found. Available profiles: $($available -join ', ')"
    }
    $Config.profiles.$ProfileName
}
