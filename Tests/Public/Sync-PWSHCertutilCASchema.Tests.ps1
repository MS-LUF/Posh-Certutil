BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force

    $script:TestJson = @'
{
  "version": "1.0",
  "profiles": {
    "test-profile": {
      "description": "Test profile",
      "defaultProfile": true,
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [
        { "fqdn": "ca01.test.local", "displayName": "CA 01" },
        { "fqdn": "ca02.test.local", "displayName": "CA 02" }
      ],
      "certutilView": {
        "restrict": {
          "issuedCerts":   "Disposition=20",
          "revokedCerts":  "Disposition=21",
          "expiringCerts": "Disposition=20,NotAfter>={EXPIRE_DATE}",
          "search":        "{DYNAMIC}"
        },
        "out": {
          "issuedCerts":   ["RequestID","CommonName","NotBefore","NotAfter","SerialNumber","BogusField"],
          "revokedCerts":  ["RequestID","CommonName","RevokedReason","RevokedEffectiveWhen"],
          "expiringCerts": ["RequestID","CommonName","NotAfter","SerialNumber"],
          "search":        ["RequestID","CommonName","Disposition"]
        }
      }
    }
  }
}
'@
    $script:TestConfigPath = [IO.Path]::GetTempFileName()
    Set-Content -Path $script:TestConfigPath -Value $script:TestJson -Encoding UTF8

    InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
        param($ConfigPath)
        $script:ConfigPath = $ConfigPath
    }

    $script:FakeSession      = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
    $script:MockSchemaFields = @(
        'RequestID', 'RequesterName', 'CommonName',
        'NotBefore', 'NotAfter', 'SerialNumber',
        'CertificateTemplate', 'Disposition',
        'RevokedReason', 'RevokedEffectiveWhen'
    )
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Sync-PWSHCertutilCASchema' -Tag Unit {

    BeforeEach {
        # Restore config to known state before each test
        Set-Content -Path $script:TestConfigPath -Value $script:TestJson -Encoding UTF8
        InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
            param($ConfigPath)
            $script:ConfigPath = $ConfigPath
        }

        Mock -ModuleName Posh-Certutil Get-CASession              { $script:FakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertutilSchema      { @('stub') }
        Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema { $script:MockSchemaFields }
        Mock -ModuleName Posh-Certutil Get-CertutilFieldNameMap   { @{} }
    }

    Context 'Schema discovery (read-only)' {
        It 'Returns one result object per CA in the profile' {
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile'
            $results | Should -HaveCount 2
            $results[0].CAServer | Should -Be 'ca01.test.local'
            $results[1].CAServer | Should -Be 'ca02.test.local'
        }

        It 'Sets Profile on every returned object' {
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile'
            $results | ForEach-Object { $_.Profile | Should -Be 'test-profile' }
        }

        It 'Populates AvailableFields and FieldCount from ConvertFrom-CertutilSchema output' {
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local'
            $result.AvailableFields | Should -Contain 'RequestID'
            $result.AvailableFields | Should -Contain 'CommonName'
            $result.FieldCount | Should -Be $script:MockSchemaFields.Count
        }

        It 'Queries only the specified CA when -CAFqdn is provided' {
            Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local' | Out-Null
            Should -Invoke -ModuleName Posh-Certutil Get-CASession -Times 1
        }

        It 'Throws when the specified -CAFqdn is not in the profile' {
            { Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca99.test.local' } |
                Should -Throw
        }

        It 'Writes an error but does not throw when one CA fails' {
            Mock -ModuleName Posh-Certutil Get-CASession {
                if ($CAFqdn -eq 'ca01.test.local') { throw 'WinRM refused' }
                $script:FakeSession
            }
            { Sync-PWSHCertutilCASchema -Profile 'test-profile' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It 'Falls back to the default profile when -Profile is omitted' {
            $results = Sync-PWSHCertutilCASchema
            $results[0].Profile | Should -Be 'test-profile'
        }

        It 'Throws when -Profile is omitted and no default profile is configured' {
            $noDefaultPath = [IO.Path]::GetTempFileName()
            '{"version":"1.0","profiles":{"other":{"description":"x","defaultProfile":false,"remoting":{"useTls":true,"port":5986,"maxSessionsPerCA":2},"cas":[],"certutilView":{"restrict":{},"out":{}}}}}' |
                Set-Content -Path $noDefaultPath -Encoding UTF8
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $noDefaultPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
            try {
                { Sync-PWSHCertutilCASchema } | Should -Throw -ExpectedMessage '*default profile*'
            } finally {
                Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
                InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                    param($ConfigPath)
                    $script:ConfigPath = $ConfigPath
                }
            }
        }
    }

    Context 'Field validation' {
        It 'ValidatedOut excludes fields absent from the schema' {
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local'
            $result.ValidatedOut.issuedCerts | Should -Not -Contain 'BogusField'
            $result.ValidatedOut.issuedCerts | Should -Contain 'RequestID'
        }

        It 'RemovedFields lists fields that are in config but missing from schema' {
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local'
            $result.RemovedFields.issuedCerts | Should -Contain 'BogusField'
        }

        It 'Uses field intersection when multiple CAs are queried' {
            $script:SchemaCallCount = 0
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema {
                $script:SchemaCallCount++
                if ($script:SchemaCallCount -eq 1) {
                    @('RequestID', 'CommonName', 'SerialNumber', 'Disposition', 'RevokedReason',
                      'RevokedEffectiveWhen', 'NotBefore', 'NotAfter', 'CertificateTemplate')
                } else {
                    # CA02 is missing CertificateTemplate — should be dropped from intersection
                    @('RequestID', 'CommonName', 'SerialNumber', 'Disposition', 'RevokedReason',
                      'RevokedEffectiveWhen', 'NotBefore', 'NotAfter')
                }
            }
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile'
            $results[0].ValidatedOut.issuedCerts | Should -Not -Contain 'CertificateTemplate'
            $results[1].ValidatedOut.issuedCerts | Should -Not -Contain 'CertificateTemplate'
        }
    }

    Context 'Schema mismatch detection' {
        It 'SchemaConflicts is empty when all CAs return identical field sets' {
            # Default mock returns the same $script:MockSchemaFields for every call
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile'
            $conflicts = $results[0].SchemaConflicts | Get-Member -MemberType NoteProperty
            $conflicts | Should -BeNullOrEmpty
        }

        It 'SchemaConflicts is empty when only one CA is queried' {
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local'
            $conflicts = $result.SchemaConflicts | Get-Member -MemberType NoteProperty
            $conflicts | Should -BeNullOrEmpty
        }

        It 'SchemaConflicts maps each divergent field to the CAs that have it' {
            $script:SchemaCallCount = 0
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema {
                $script:SchemaCallCount++
                if ($script:SchemaCallCount -eq 1) {
                    @('RequestID', 'CommonName', 'CertificateTemplate')
                } else {
                    @('RequestID', 'CommonName')   # CA02 lacks CertificateTemplate
                }
            }
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile' -WarningAction SilentlyContinue
            $results[0].SchemaConflicts.CertificateTemplate | Should -Contain 'ca01.test.local'
            $results[0].SchemaConflicts.CertificateTemplate | Should -Not -Contain 'ca02.test.local'
        }

        It 'Both result objects carry the same SchemaConflicts map' {
            $script:SchemaCallCount = 0
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema {
                $script:SchemaCallCount++
                if ($script:SchemaCallCount -eq 1) {
                    @('RequestID', 'CommonName', 'CertificateTemplate')
                } else {
                    @('RequestID', 'CommonName')
                }
            }
            $results = Sync-PWSHCertutilCASchema -Profile 'test-profile' -WarningAction SilentlyContinue
            # The conflict map is profile-wide, not per-CA
            $results[0].SchemaConflicts.CertificateTemplate |
                Should -Be $results[1].SchemaConflicts.CertificateTemplate
        }

        It 'Emits a warning for each field that is not present on every CA' {
            $script:SchemaCallCount = 0
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema {
                $script:SchemaCallCount++
                if ($script:SchemaCallCount -eq 1) {
                    @('RequestID', 'CommonName', 'CertificateTemplate', 'RequesterName')
                } else {
                    @('RequestID', 'CommonName')   # missing CertificateTemplate + RequesterName
                }
            }
            $caught = $null
            Sync-PWSHCertutilCASchema -Profile 'test-profile' `
                -WarningVariable caught -WarningAction SilentlyContinue | Out-Null
            # One warning per conflicting field
            $caught | Should -HaveCount 2
            $caught | Where-Object { $_ -match 'CertificateTemplate' } | Should -Not -BeNullOrEmpty
            $caught | Where-Object { $_ -match 'RequesterName' }       | Should -Not -BeNullOrEmpty
        }

        It 'Warning message identifies both the field and the CAs involved' {
            $script:SchemaCallCount = 0
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilSchema {
                $script:SchemaCallCount++
                if ($script:SchemaCallCount -eq 1) {
                    @('RequestID', 'CommonName', 'CertificateTemplate')
                } else {
                    @('RequestID', 'CommonName')
                }
            }
            $caught = $null
            Sync-PWSHCertutilCASchema -Profile 'test-profile' `
                -WarningVariable caught -WarningAction SilentlyContinue | Out-Null
            $caught[0] | Should -Match 'Schema mismatch'
            $caught[0] | Should -Match 'CertificateTemplate'
            $caught[0] | Should -Match 'ca01.test.local'
            $caught[0] | Should -Match 'ca02.test.local'
        }
    }

    Context 'Config update (-UpdateConfig)' {
        It 'ConfigUpdated is $false without -UpdateConfig' {
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local'
            $result.ConfigUpdated | Should -Be $false
        }

        It 'ConfigUpdated is $true when -UpdateConfig writes the file' {
            Mock -ModuleName Posh-Certutil Set-Content {}
            $result = Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local' -UpdateConfig
            $result.ConfigUpdated | Should -Be $true
        }

        It 'Does not write the file when -WhatIf is specified' {
            Mock -ModuleName Posh-Certutil Set-Content {}
            Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local' -UpdateConfig -WhatIf
            Should -Invoke -ModuleName Posh-Certutil Set-Content -Times 0
        }

        It 'Writes JSON with invalid fields removed and valid fields preserved' {
            # Let Set-Content write to the real temp file; restore happens in BeforeEach
            Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local' -UpdateConfig

            $updated = Get-Content -Path $script:TestConfigPath -Raw | ConvertFrom-Json
            $out = $updated.profiles.'test-profile'.certutilView.out
            $out.issuedCerts | Should -Not -Contain 'BogusField'
            $out.issuedCerts | Should -Contain 'RequestID'
            $out.issuedCerts | Should -Contain 'CommonName'
        }

        It 'Writes syncState.lastSync and fieldNameMap when -UpdateConfig succeeds' {
            Mock -ModuleName Posh-Certutil Get-CertutilFieldNameMap {
                @{ 'Issued Request ID' = 'RequestID'; 'Issued Common Name' = 'CommonName' }
            }
            Sync-PWSHCertutilCASchema -Profile 'test-profile' -CAFqdn 'ca01.test.local' -UpdateConfig

            $updated = Get-Content -Path $script:TestConfigPath -Raw | ConvertFrom-Json
            $syncState = $updated.profiles.'test-profile'.syncState
            $syncState.lastSync | Should -Not -BeNullOrEmpty
            $syncState.fieldNameMap.'Issued Request ID' | Should -Be 'RequestID'
            $syncState.fieldNameMap.'Issued Common Name' | Should -Be 'CommonName'
        }
    }
}
