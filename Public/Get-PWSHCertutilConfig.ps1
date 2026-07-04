function Get-PWSHCertutilConfig {
    <#
    .SYNOPSIS
        Reads and displays the Posh-Certutil configuration as PowerShell objects.
    .DESCRIPTION
        Reads the embedded Posh-Certutil.json configuration file and returns its contents
        as structured PowerShell objects. Returns all profiles unless -Profile is specified.
    .PARAMETER Profile
        Name of a specific profile to return. If omitted, all profiles are returned.
    .EXAMPLE
        Get-PWSHCertutilConfig
        Returns all profiles from the configuration file.
    .EXAMPLE
        Get-PWSHCertutilConfig -Profile 'prod-pki'
        Returns only the 'prod-pki' profile configuration.
    .OUTPUTS
        PSCustomObject. One object per profile with Profile (name) and Config properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string] $Profile
    )

    $config = Read-ConfigFile

    if ($PSBoundParameters.ContainsKey('Profile')) {
        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile
        [PSCustomObject]@{
            Profile = $Profile
            Config  = $profileConfig
        }
    } else {
        foreach ($name in $config.profiles.PSObject.Properties.Name) {
            [PSCustomObject]@{
                Profile = $name
                Config  = $config.profiles.$name
            }
        }
    }
}
