function New-ProfileDynamicParameter {
    param(
        [Parameter()] [bool] $Mandatory = $false,
        [Parameter()] [string] $ParameterSetName
    )

    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $attributes      = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

    $parameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $parameterAttribute.Mandatory = $Mandatory
    if ($ParameterSetName) { $parameterAttribute.ParameterSetName = $ParameterSetName }
    $attributes.Add($parameterAttribute)

    # Read fresh on every call (no cache) so newly added/removed profiles are reflected immediately.
    $config       = Read-ConfigFile
    $profileNames = @(foreach ($name in $config.profiles.PSObject.Properties.Name) { $name })
    if ($profileNames.Count -gt 0) {
        $attributes.Add([System.Management.Automation.ValidateSetAttribute]::new([string[]]$profileNames))
    }

    $runtimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new('Profile', [string], $attributes)
    $paramDictionary.Add('Profile', $runtimeParameter)
    $paramDictionary
}
