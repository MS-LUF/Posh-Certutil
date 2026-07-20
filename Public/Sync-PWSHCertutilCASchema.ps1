function Sync-PWSHCertutilCASchema {
    <#
    .SYNOPSIS
        Discovers the CA database schema from CAs in a profile and optionally updates the configuration.
    .DESCRIPTION
        Connects to each CA defined in the profile via WinRM and runs certutil -schema to retrieve
        all available database column names. Returns one object per CA with Profile, CAServer, and
        AvailableFields properties.

        When -UpdateConfig is specified, the cmdlet computes the intersection of fields available
        across ALL queried CAs, validates the profile's certutilView.out arrays against that set,
        removes any field names that do not exist in the schema, and writes the corrected
        configuration back to Posh-Certutil.json. This is the correct first step to take after
        pointing the module at a new CA environment to ensure the configured field names match the
        actual CA database schema. Supports -WhatIf.

        When multiple CAs are queried and their schemas differ (e.g. due to CA version drift or
        differing configurations), a warning is emitted for each conflicting field identifying
        which CAs have it and which do not. The SchemaConflicts property on each result object
        maps every such field to the list of CAs that expose it.
    .PARAMETER Profile
        The configuration profile to use. Optional; falls back to the profile marked as
        default (see Set-PWSHCertutilConfig -DefaultProfile) when omitted. Throws if omitted
        and no default profile is configured.
    .PARAMETER CAFqdn
        Optional. Queries only this CA instead of all CAs in the profile. When -UpdateConfig is
        also specified, validation uses only this CA's schema.
    .PARAMETER UpdateConfig
        When present, validates the profile's certutilView.out field lists against the discovered
        schema and writes corrections to Posh-Certutil.json.
    .PARAMETER Credential
        Optional PSCredential for WinRM. Defaults to current user.
    .EXAMPLE
        Sync-PWSHCertutilCASchema -Profile 'prod-pki'
        Discovers and returns the schema from every CA in 'prod-pki' without modifying the config.
    .EXAMPLE
        Sync-PWSHCertutilCASchema -Profile 'prod-pki' -UpdateConfig
        Discovers the schema and removes any out field names that do not exist in the CA database.
    .EXAMPLE
        Sync-PWSHCertutilCASchema -Profile 'prod-pki' -UpdateConfig -WhatIf
        Shows what changes would be made to the config without writing them.
    .OUTPUTS
        PSCustomObject[]. One object per CA with Profile, CAServer, AvailableFields, FieldCount,
        SchemaConflicts, ValidatedOut, RemovedFields, and ConfigUpdated properties.
        SchemaConflicts is a PSCustomObject whose properties are field names that are not present
        on every queried CA; each property value is the array of CA FQDNs that expose that field.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string] $CAFqdn,

        [Parameter()]
        [switch] $UpdateConfig,

        [Parameter()]
        [pscredential] $Credential
    )

    dynamicparam {
        New-ProfileDynamicParameter
    }

    process {
        $Profile = $PSBoundParameters['Profile']

        $config        = Read-ConfigFile
        $Profile       = Resolve-ProfileName -Config $config -ProfileName $Profile
        $profileConfig = Get-ProfileConfig -Config $config -ProfileName $Profile

        $cas = if ($PSBoundParameters.ContainsKey('CAFqdn')) {
            $found = $profileConfig.cas | Where-Object { $_.fqdn -eq $CAFqdn }
            if (-not $found) { throw "CA '$CAFqdn' is not defined in profile '$Profile'." }
            $found
        } else { $profileConfig.cas }

        # Collect schema from each CA
        $schemaPerCA = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($ca in $cas) {
            try {
                $sessionArgs = @{ CAFqdn = $ca.fqdn; RemotingConfig = $profileConfig.remoting }
                if ($PSBoundParameters.ContainsKey('Credential')) { $sessionArgs['Credential'] = $Credential }
                $session = Get-CASession @sessionArgs

                $rawOutput = Invoke-CertutilSchema -Session $session
                $fields    = @(ConvertFrom-CertutilSchema -RawOutput $rawOutput)

                $schemaPerCA.Add([PSCustomObject]@{ CAFqdn = $ca.fqdn; Fields = $fields })
                Write-Verbose "CA '$($ca.fqdn)': $($fields.Count) schema fields discovered."
            } catch {
                Write-Error "Failed to retrieve schema from '$($ca.fqdn)': $_"
            }
        }

        if ($schemaPerCA.Count -eq 0) {
            Write-Error "No schema data retrieved from any CA in profile '$Profile'."
            return
        }

        # Intersection of fields available on ALL queried CAs ensures config works across all of them
        $intersection = $schemaPerCA[0].Fields
        foreach ($entry in @($schemaPerCA)[1..($schemaPerCA.Count - 1)]) {
            $intersection = @($intersection | Where-Object { $entry.Fields -contains $_ })
        }

        # Detect fields that exist on some CAs but not all — these indicate schema version drift
        $conflictMap = @{}
        if ($schemaPerCA.Count -gt 1) {
            $allFields = @($schemaPerCA | ForEach-Object { $_.Fields } | Sort-Object -Unique)
            foreach ($field in $allFields) {
                $casWithField = @($schemaPerCA |
                    Where-Object { $_.Fields -contains $field } |
                    ForEach-Object { $_.CAFqdn })
                if ($casWithField.Count -lt $schemaPerCA.Count) {
                    $conflictMap[$field] = $casWithField
                }
            }
            foreach ($field in ($conflictMap.Keys | Sort-Object)) {
                $hasIt   = $conflictMap[$field] -join ', '
                $missing = ($schemaPerCA |
                    Where-Object { $_.Fields -notcontains $field } |
                    ForEach-Object { $_.CAFqdn }) -join ', '
                Write-Warning "Schema mismatch: field '$field' exists on [$hasIt] but not on [$missing]. It will be excluded from the validated field set for this profile."
            }
        }

        # Validate current out arrays against the intersection
        $operations    = @('issuedCerts', 'revokedCerts', 'expiringCerts', 'search')
        $validatedOut  = [ordered]@{}
        $removedFields = [ordered]@{}

        foreach ($op in $operations) {
            $currentFields = $profileConfig.certutilView.out.$op
            if ($null -eq $currentFields) {
                $validatedOut[$op]  = @()
                $removedFields[$op] = @()
                continue
            }
            $validatedOut[$op]  = @($currentFields | Where-Object { $intersection -contains $_ })
            $removedFields[$op] = @($currentFields | Where-Object { $intersection -notcontains $_ })
        }

        $configUpdated = $false

        if ($UpdateConfig) {
            $target = "certutilView.out field lists for profile '$Profile'"
            if ($PSCmdlet.ShouldProcess($target, 'Remove schema-invalid fields')) {
                foreach ($op in $operations) {
                    if ($null -ne $profileConfig.certutilView.out.$op) {
                        $profileConfig.certutilView.out |
                            Add-Member -MemberType NoteProperty -Name $op -Value $validatedOut[$op] -Force
                    }
                }

                # Build field name map from a probe query against the first CA
                try {
                    $probeCA   = $schemaPerCA[0].CAFqdn
                    $probeArgs = @{ CAFqdn = $probeCA; RemotingConfig = $profileConfig.remoting }
                    if ($PSBoundParameters.ContainsKey('Credential')) { $probeArgs['Credential'] = $Credential }
                    $probeSession = Get-CASession @probeArgs

                    $allCanonical = [System.Collections.Generic.List[string]]::new()
                    foreach ($op in $operations) {
                        $fields = $profileConfig.certutilView.out.$op
                        if ($fields) {
                            foreach ($f in $fields) {
                                if (-not $allCanonical.Contains($f)) { $allCanonical.Add($f) }
                            }
                        }
                    }
                    # Filter to intersection — every field we probe must exist on the CA
                    $validCanonical = @($allCanonical | Where-Object { $intersection -contains $_ })

                    $fieldMap  = Get-CertutilFieldNameMap -Session $probeSession -CanonicalFieldNames $validCanonical
                    $syncState = [PSCustomObject]@{
                        lastSync     = [datetime]::UtcNow.ToString('o')
                        fieldNameMap = [PSCustomObject]$fieldMap
                    }
                    $profileConfig | Add-Member -MemberType NoteProperty -Name 'syncState' -Value $syncState -Force
                    Write-Verbose "Field name map built from probe query against '$probeCA'."
                } catch {
                    Write-Warning "Could not build field name map for profile '$Profile': $_"
                }

                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigPath -Encoding UTF8
                $configUpdated = $true
                Write-Verbose "Profile '$Profile' out fields updated in $script:ConfigPath"
            }
        }

        foreach ($entry in $schemaPerCA) {
            [PSCustomObject]@{
                Profile         = $Profile
                CAServer        = $entry.CAFqdn
                AvailableFields = $entry.Fields
                FieldCount      = $entry.Fields.Count
                SchemaConflicts = [PSCustomObject]$conflictMap
                ValidatedOut    = [PSCustomObject]$validatedOut
                RemovedFields   = [PSCustomObject]$removedFields
                ConfigUpdated   = $configUpdated
            }
        }
    }
}
