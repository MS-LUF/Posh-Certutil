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

    Describe 'Test-CASession' -Tag Unit {
        BeforeAll {
            $goodSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns $true when Invoke-Command succeeds' {
            Mock Invoke-Command { $true }
            $result = Test-CASession -Session $goodSession
            $result | Should -Be $true
        }

        It 'Returns $false when Invoke-Command throws' {
            Mock Invoke-Command { throw 'connection lost' }
            $result = Test-CASession -Session $goodSession
            $result | Should -Be $false
        }
    }

    Describe 'Remove-CASession' -Tag Unit {
        BeforeEach {
            $script:SessionPool.Clear()
        }

        It 'Removes an existing entry from the pool' {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
            $script:SessionPool['ca01.test.local:5986'] = [PSCustomObject]@{ Session = $mockSession }
            Mock Remove-PSSession {}
            Remove-CASession -CAFqdn 'ca01.test.local' -Port 5986
            $script:SessionPool.ContainsKey('ca01.test.local:5986') | Should -Be $false
        }

        It 'Does not throw when the key does not exist' {
            { Remove-CASession -CAFqdn 'ca99.test.local' -Port 5986 } | Should -Not -Throw
        }
    }

    Describe 'Get-CASession' -Tag Unit {
        BeforeEach {
            $script:SessionPool.Clear()
            $remotingConfig = [PSCustomObject]@{ port = 5986; useTls = $true; maxSessionsPerCA = 2 }
        }

        Context 'When a live session exists in the pool' {
            It 'Returns the existing session without creating a new one' {
                $existingSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
                $script:SessionPool['ca01.test.local:5986'] = [PSCustomObject]@{
                    Session  = $existingSession
                    CAFqdn   = 'ca01.test.local'
                    LastUsed = [datetime]::UtcNow
                }
                Mock Test-CASession { $true }
                Mock New-PSSession {}

                $result = Get-CASession -CAFqdn 'ca01.test.local' -RemotingConfig $remotingConfig
                $result | Should -Be $existingSession
                Should -Invoke New-PSSession -Times 0
            }
        }

        Context 'When the pool entry is dead' {
            It 'Evicts the dead session and creates a new one' {
                $deadSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
                $script:SessionPool['ca01.test.local:5986'] = [PSCustomObject]@{
                    Session  = $deadSession
                    CAFqdn   = 'ca01.test.local'
                    LastUsed = [datetime]::UtcNow
                }
                Mock Test-CASession { $false }
                Mock Remove-PSSession {}
                Mock New-PSSession { New-MockObject -Type System.Management.Automation.Runspaces.PSSession }

                Get-CASession -CAFqdn 'ca01.test.local' -RemotingConfig $remotingConfig | Out-Null
                Should -Invoke Remove-PSSession -Times 1
                Should -Invoke New-PSSession -Times 1
            }
        }

        Context 'When no pool entry exists' {
            It 'Creates a new session with UseSSL when useTls is true' {
                Mock New-PSSession { New-MockObject -Type System.Management.Automation.Runspaces.PSSession }

                $result = Get-CASession -CAFqdn 'ca01.test.local' -RemotingConfig $remotingConfig
                $result | Should -Not -BeNullOrEmpty
                Should -Invoke New-PSSession -ParameterFilter { $UseSSL -eq $true } -Times 1
            }

            It 'Creates a new session without UseSSL when useTls is false' {
                $nonTlsConfig = [PSCustomObject]@{ port = 5985; useTls = $false; maxSessionsPerCA = 2 }
                Mock New-PSSession { New-MockObject -Type System.Management.Automation.Runspaces.PSSession }

                Get-CASession -CAFqdn 'ca01.test.local' -RemotingConfig $nonTlsConfig | Out-Null
                Should -Invoke New-PSSession -ParameterFilter { -not $UseSSL } -Times 1
            }

            It 'Stores the new session in the pool' {
                Mock New-PSSession { New-MockObject -Type System.Management.Automation.Runspaces.PSSession }

                Get-CASession -CAFqdn 'ca01.test.local' -RemotingConfig $remotingConfig | Out-Null
                $script:SessionPool.ContainsKey('ca01.test.local:5986') | Should -Be $true
            }
        }
    }
}
