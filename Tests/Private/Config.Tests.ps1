BeforeDiscovery {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

AfterAll {
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

InModuleScope Posh-Certutil {

    Describe 'Read-ConfigFile' -Tag Unit {
        BeforeEach {
            $testJson = @'
{
  "version": "1.0",
  "profiles": {
    "test-profile": {
      "description": "Test",
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [{ "fqdn": "ca01.test.local", "displayName": "CA01" }],
      "certutilView": {
        "restrict": { "issuedCerts": "GeneralFlags=0,Disposition=20" },
        "out":      { "issuedCerts": ["RequestID","CommonName"] }
      }
    }
  }
}
'@
            $tempPath = [IO.Path]::GetTempFileName()
            Set-Content -Path $tempPath -Value $testJson -Encoding UTF8
            $script:ConfigPath = $tempPath
        }

        AfterEach {
            Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
            $script:ConfigPath = Join-Path $script:ModuleRoot 'Config\Posh-Certutil.json'
        }

        Context 'When the config file exists' {
            It 'Returns a PSCustomObject with profiles' {
                $result = Read-ConfigFile
                $result | Should -Not -BeNullOrEmpty
                $result.profiles.PSObject.Properties.Name | Should -Contain 'test-profile'
            }
        }

        Context 'When the config file does not exist' {
            It 'Returns an empty profiles object without throwing' {
                $script:ConfigPath = 'C:\DoesNotExist\missing.json'
                $result = Read-ConfigFile
                $result.profiles.PSObject.Properties.Name | Should -BeNullOrEmpty
            }
        }
    }

    Describe 'Get-ProfileConfig' -Tag Unit {
        BeforeAll {
            $mockConfig = [PSCustomObject]@{
                profiles = [PSCustomObject]@{
                    'prod-pki' = [PSCustomObject]@{ description = 'Production' }
                }
            }
        }

        Context 'When the profile exists' {
            It 'Returns the profile object' {
                $result = Get-ProfileConfig -Config $mockConfig -ProfileName 'prod-pki'
                $result.description | Should -Be 'Production'
            }
        }

        Context 'When the profile does not exist' {
            It 'Throws with the available profile names in the message' {
                { Get-ProfileConfig -Config $mockConfig -ProfileName 'nonexistent' } |
                    Should -Throw -ExpectedMessage '*prod-pki*'
            }
        }
    }

    Describe 'Invoke-ProfileAutoSync' -Tag Unit {
        BeforeAll {
            $script:SyncTestJson = @'
{
  "version": "1.0",
  "profiles": {
    "no-sync": {
      "description": "Not yet synced",
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [{ "fqdn": "ca01.test.local", "displayName": "CA01" }],
      "certutilView": {
        "restrict": { "issuedCerts": "Disposition=20" },
        "out": { "issuedCerts": ["RequestID","CommonName"] }
      },
      "syncState": null
    },
    "already-synced": {
      "description": "Already synced",
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [{ "fqdn": "ca01.test.local", "displayName": "CA01" }],
      "certutilView": {
        "restrict": { "issuedCerts": "Disposition=20" },
        "out": { "issuedCerts": ["RequestID","CommonName"] }
      },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": { "RequestID": "RequestID" }
      }
    }
  }
}
'@
        }

        BeforeEach {
            $syncTempPath = [IO.Path]::GetTempFileName()
            Set-Content -Path $syncTempPath -Value $script:SyncTestJson -Encoding UTF8
            $script:ConfigPath = $syncTempPath
        }

        AfterEach {
            Remove-Item -Path $syncTempPath -ErrorAction SilentlyContinue
            $script:ConfigPath = Join-Path $script:ModuleRoot 'Config\Posh-Certutil.json'
        }

        It 'Returns profileConfig unchanged when syncState.lastSync is already set' {
            $cfg     = Read-ConfigFile
            $profile = Get-ProfileConfig -Config $cfg -ProfileName 'already-synced'
            $result  = Invoke-ProfileAutoSync -Config $cfg -ProfileName 'already-synced' -ProfileConfig $profile
            $result.syncState.lastSync | Should -Not -BeNullOrEmpty
            $result.syncState.fieldNameMap.RequestID | Should -Be 'RequestID'
        }

        It 'Emits a warning and calls Get-CertutilFieldNameMap when no syncState exists' {
            $fakeSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
            Mock Get-CASession { $fakeSession }
            Mock Get-CertutilFieldNameMap { @{ 'Issued Request ID' = 'RequestID' } }

            $cfg     = Read-ConfigFile
            $profile = Get-ProfileConfig -Config $cfg -ProfileName 'no-sync'

            $warnings = $null
            Invoke-ProfileAutoSync -Config $cfg -ProfileName 'no-sync' -ProfileConfig $profile `
                -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
            $warnings[0] | Should -Match 'no-sync'
            Should -Invoke Get-CertutilFieldNameMap -Times 1
        }

        It 'Emits a warning and returns profileConfig unchanged when auto-sync fails' {
            Mock Get-CASession { throw 'WinRM unreachable' }

            $cfg     = Read-ConfigFile
            $profile = Get-ProfileConfig -Config $cfg -ProfileName 'no-sync'

            $warnings = $null
            $result = Invoke-ProfileAutoSync -Config $cfg -ProfileName 'no-sync' -ProfileConfig $profile `
                          -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Where-Object { $_ -match 'Auto-sync failed' } | Should -Not -BeNullOrEmpty
            $result.syncState | Should -BeNullOrEmpty
        }
    }

    Describe 'Get-CertutilViewParams' -Tag Unit {
        BeforeAll {
            $mockProfile = [PSCustomObject]@{
                certutilView = [PSCustomObject]@{
                    restrict = [PSCustomObject]@{
                        issuedCerts   = 'GeneralFlags=0,Disposition=20'
                        expiringCerts = 'GeneralFlags=0,NotAfter>={EXPIRE_DATE}'
                    }
                    out = [PSCustomObject]@{
                        issuedCerts   = @('RequestID', 'CommonName')
                        expiringCerts = @('RequestID', 'NotAfter')
                    }
                }
            }
        }

        It 'Returns Restrict and Out strings for issuedCerts' {
            $result = Get-CertutilViewParams -ProfileConfig $mockProfile -Operation 'issuedCerts'
            $result.Restrict | Should -Be 'GeneralFlags=0,Disposition=20'
            $result.Out      | Should -Be 'RequestID,CommonName'
        }

        It 'Substitutes {EXPIRE_DATE} token' {
            $date   = '12/31/2025'
            $result = Get-CertutilViewParams -ProfileConfig $mockProfile -Operation 'expiringCerts' `
                          -Substitutions @{ EXPIRE_DATE = $date }
            $result.Restrict | Should -BeLike "*$date*"
            $result.Restrict | Should -Not -BeLike '*{EXPIRE_DATE}*'
        }

        It 'Throws when the operation key is missing from restrict' {
            { Get-CertutilViewParams -ProfileConfig $mockProfile -Operation 'revokedCerts' } |
                Should -Throw
        }
    }
}
