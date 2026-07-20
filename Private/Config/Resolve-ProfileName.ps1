function Resolve-ProfileName {
    param(
        [Parameter(Mandatory)] [object] $Config,
        [Parameter()] [string] $ProfileName
    )

    if ($ProfileName) { return $ProfileName }

    $defaultNames = @(
        foreach ($name in $Config.profiles.PSObject.Properties.Name) {
            if ($Config.profiles.$name.defaultProfile -eq $true) { $name }
        }
    )

    if ($defaultNames.Count -eq 0) {
        throw "No -Profile specified and no default profile is configured. Set one with: Set-PWSHCertutilConfig -Profile <name> -CAFqdn <fqdn> -DefaultProfile `$true"
    }

    $defaultNames[0]
}
