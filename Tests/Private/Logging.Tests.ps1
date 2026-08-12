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

    Describe 'Get-LoggingConfig' -Tag Unit {
        BeforeEach {
            $script:LoggingConfigWarned = $false
        }

        It 'Defaults Enabled to $false when Logging key is absent entirely' {
            $config = [PSCustomObject]@{ profiles = [PSCustomObject]@{} }
            $result = Get-LoggingConfig -Config $config
            $result.Enabled | Should -Be $false
        }

        It 'Defaults MinimumLevel, Mode, and nested File/EventLog values' {
            $config = [PSCustomObject]@{ profiles = [PSCustomObject]@{} }
            $result = Get-LoggingConfig -Config $config
            $result.MinimumLevel              | Should -Be 'Information'
            $result.Mode                      | Should -Be 'File'
            $result.File.FileName             | Should -Be 'Posh-Certutil-{yyyyMMdd}.log'
            $result.EventLog.LogName          | Should -Be 'Application'
            $result.EventLog.Source           | Should -Be 'Posh-Certutil'
            $result.EventLog.EventIdInformation | Should -Be 1000
            $result.EventLog.EventIdWarning     | Should -Be 2000
            $result.EventLog.EventIdError       | Should -Be 3000
        }

        It 'Returns the configured values when the Logging section is fully populated' {
            $config = [PSCustomObject]@{
                Logging = [PSCustomObject]@{
                    Enabled      = $true
                    MinimumLevel = 'Debug'
                    Mode         = 'EventLog'
                    File         = [PSCustomObject]@{ Path = 'C:\Logs'; FileName = 'app-{yyyyMMdd}.log' }
                    EventLog     = [PSCustomObject]@{
                        LogName = 'CustomLog'; Source = 'MySource'
                        EventIdInformation = 1; EventIdWarning = 2; EventIdError = 3
                    }
                }
            }
            $result = Get-LoggingConfig -Config $config
            $result.Enabled              | Should -Be $true
            $result.MinimumLevel         | Should -Be 'Debug'
            $result.Mode                 | Should -Be 'EventLog'
            $result.File.Path            | Should -Be 'C:\Logs'
            $result.EventLog.Source      | Should -Be 'MySource'
            $result.EventLog.EventIdError | Should -Be 3
        }

        It 'Falls back to Information and warns when MinimumLevel is not a known level' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ MinimumLevel = 'Verbose' } }
            $warnings = $null
            $result = Get-LoggingConfig -Config $config -WarningVariable warnings -WarningAction SilentlyContinue
            $result.MinimumLevel | Should -Be 'Information'
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Falls back to File and warns when Mode is not File or EventLog' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Mode = 'Syslog' } }
            $warnings = $null
            $result = Get-LoggingConfig -Config $config -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Mode | Should -Be 'File'
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Resolve-LogFilePath' -Tag Unit {
        BeforeEach {
            $script:TestLogDir = Join-Path $env:TEMP "PoshCertutilLogTest-$([guid]::NewGuid())"
        }

        AfterEach {
            Remove-Item -Path $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Expands environment variables in Path' {
            $file = [PSCustomObject]@{ Path = '%TEMP%\PoshCertutilLogTest-EnvExpand'; FileName = 'x.log' }
            $result = Resolve-LogFilePath -File $file
            $result | Should -Not -BeLike '*%TEMP%*'
            $result | Should -BeLike "*$env:TEMP*"
            Remove-Item -Path (Split-Path $result -Parent) -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Expands a {DateFormat} token in FileName using the current date' {
            $file = [PSCustomObject]@{ Path = $script:TestLogDir; FileName = 'app-{yyyyMMdd}.log' }
            $result = Resolve-LogFilePath -File $file
            $expected = "app-$((Get-Date).ToString('yyyyMMdd')).log"
            (Split-Path $result -Leaf) | Should -Be $expected
        }

        It 'Creates the target directory when it does not exist' {
            Test-Path $script:TestLogDir | Should -Be $false
            $file = [PSCustomObject]@{ Path = $script:TestLogDir; FileName = 'x.log' }
            Resolve-LogFilePath -File $file | Out-Null
            Test-Path $script:TestLogDir | Should -Be $true
        }
    }

    Describe 'Write-FileLogEntry' -Tag Unit {
        BeforeEach {
            $script:TestLogDir = Join-Path $env:TEMP "PoshCertutilLogTest-$([guid]::NewGuid())"
            $script:LoggingSinkFailed = $false
        }

        AfterEach {
            Remove-Item -Path $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Appends a formatted line containing level, user, cmdlet, and message' {
            $file  = [PSCustomObject]@{ Path = $script:TestLogDir; FileName = 'x.log' }
            $entry = [PSCustomObject]@{
                Timestamp = Get-Date; Level = 'Debug'; UserName = 'DOMAIN\alice'
                CmdletName = 'Test-Cmdlet'; ProfileName = 'prod'; CAServer = 'ca01'; Message = 'hello'
            }
            Write-FileLogEntry -File $file -Entry $entry
            $line = Get-Content -Path (Join-Path $script:TestLogDir 'x.log')
            $line | Should -BeLike '*[DEBUG]*'
            $line | Should -BeLike '*DOMAIN\alice*'
            $line | Should -BeLike '*Test-Cmdlet*'
            $line | Should -BeLike '*Profile=prod*'
            $line | Should -BeLike '*CAServer=ca01*'
            $line | Should -BeLike '*hello*'
        }

        It 'Does not throw and warns once when the destination cannot be written' {
            Mock Resolve-LogFilePath { throw 'access denied' }
            $file  = [PSCustomObject]@{ Path = $script:TestLogDir; FileName = 'x.log' }
            $entry = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Error'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            $warnings = $null
            Write-FileLogEntry -File $file -Entry $entry -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -Not -BeNullOrEmpty
            $script:LoggingSinkFailed | Should -Be $true
        }
    }

    Describe 'Write-EventLogEntry' -Tag Unit {
        BeforeEach {
            $script:LoggingSinkFailed = $false
        }

        It 'Creates the event source when it does not already exist' {
            Mock Test-EventSourceExists { $false }
            Mock New-EventLog {}
            Mock Write-EventLog {}

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Information'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            Write-EventLogEntry -EventLog $eventLog -Entry $entry
            Should -Invoke New-EventLog -Times 1 -ParameterFilter { $LogName -eq 'Application' -and $Source -eq 'Posh-Certutil' }
        }

        It 'Skips source creation when the source already exists' {
            Mock Test-EventSourceExists { $true }
            Mock New-EventLog {}
            Mock Write-EventLog {}

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Information'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            Write-EventLogEntry -EventLog $eventLog -Entry $entry
            Should -Invoke New-EventLog -Times 0
        }

        It 'Writes with EventIdWarning and EntryType Warning for Level Warning' {
            Mock Test-EventSourceExists { $true }
            Mock Write-EventLog {}

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Warning'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            Write-EventLogEntry -EventLog $eventLog -Entry $entry
            Should -Invoke Write-EventLog -Times 1 -ParameterFilter {
                $EventId -eq 2000 -and $EntryType -eq [System.Diagnostics.EventLogEntryType]::Warning
            }
        }

        It 'Writes with EventIdError and EntryType Error for Level Error' {
            Mock Test-EventSourceExists { $true }
            Mock Write-EventLog {}

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Error'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            Write-EventLogEntry -EventLog $eventLog -Entry $entry
            Should -Invoke Write-EventLog -Times 1 -ParameterFilter {
                $EventId -eq 3000 -and $EntryType -eq [System.Diagnostics.EventLogEntryType]::Error
            }
        }

        It 'Writes Debug-level entries as EventIdInformation/Information with a [DEBUG] prefix' {
            Mock Test-EventSourceExists { $true }
            Mock Write-EventLog {}

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Debug'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            Write-EventLogEntry -EventLog $eventLog -Entry $entry
            Should -Invoke Write-EventLog -Times 1 -ParameterFilter {
                $EventId -eq 1000 -and $EntryType -eq [System.Diagnostics.EventLogEntryType]::Information -and $Message -like '*[DEBUG]*'
            }
        }

        It 'Does not throw and warns once when writing to the event log fails' {
            Mock Test-EventSourceExists { $true }
            Mock Write-EventLog { throw 'access denied' }

            $eventLog = [PSCustomObject]@{ LogName = 'Application'; Source = 'Posh-Certutil'; EventIdInformation = 1000; EventIdWarning = 2000; EventIdError = 3000 }
            $entry    = [PSCustomObject]@{ Timestamp = Get-Date; Level = 'Information'; UserName = 'u'; CmdletName = 'c'; Message = 'm' }

            $warnings = $null
            Write-EventLogEntry -EventLog $eventLog -Entry $entry -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -Not -BeNullOrEmpty
            $script:LoggingSinkFailed | Should -Be $true
        }
    }

    Describe 'Write-PWSHCertutilLog' -Tag Unit {
        BeforeEach {
            $script:LoggingSinkFailed = $false
            $script:LoggingConfigWarned = $false
            Mock Write-FileLogEntry {}
            Mock Write-EventLogEntry {}
        }

        It 'No-ops without dispatching when Logging.Enabled is $false' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $false } }
            Write-PWSHCertutilLog -Config $config -Level Error -CmdletName 'Test' -Message 'm'
            Should -Invoke Write-FileLogEntry -Times 0
            Should -Invoke Write-EventLogEntry -Times 0
        }

        It 'No-ops when the entry Level is below MinimumLevel' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $true; MinimumLevel = 'Warning'; Mode = 'File' } }
            Write-PWSHCertutilLog -Config $config -Level Information -CmdletName 'Test' -Message 'm'
            Should -Invoke Write-FileLogEntry -Times 0
        }

        It 'Dispatches to Write-FileLogEntry when Mode is File and Level meets MinimumLevel' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $true; MinimumLevel = 'Debug'; Mode = 'File' } }
            Write-PWSHCertutilLog -Config $config -Level Debug -CmdletName 'Test' -Message 'm'
            Should -Invoke Write-FileLogEntry -Times 1
            Should -Invoke Write-EventLogEntry -Times 0
        }

        It 'Dispatches to Write-EventLogEntry when Mode is EventLog' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $true; MinimumLevel = 'Debug'; Mode = 'EventLog' } }
            Write-PWSHCertutilLog -Config $config -Level Debug -CmdletName 'Test' -Message 'm'
            Should -Invoke Write-EventLogEntry -Times 1
            Should -Invoke Write-FileLogEntry -Times 0
        }

        It 'Stamps the current Windows identity on the entry' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $true; MinimumLevel = 'Debug'; Mode = 'File' } }
            Write-PWSHCertutilLog -Config $config -Level Debug -CmdletName 'Test' -Message 'm'
            Should -Invoke Write-FileLogEntry -Times 1 -ParameterFilter {
                $Entry.UserName -eq [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
        }

        It 'Redacts Credential/Password/Secret/Token-named bound parameters' {
            $config = [PSCustomObject]@{ Logging = [PSCustomObject]@{ Enabled = $true; MinimumLevel = 'Debug'; Mode = 'File' } }
            $bound  = @{ Profile = 'prod'; Credential = 'should-not-appear'; ApiToken = 'should-not-appear-either' }
            Write-PWSHCertutilLog -Config $config -Level Debug -CmdletName 'Test' -Message 'm' -BoundParameters $bound
            Should -Invoke Write-FileLogEntry -Times 1 -ParameterFilter {
                $Entry.Message -notlike '*should-not-appear*' -and $Entry.Message -like '*<redacted>*' -and $Entry.Message -like '*Profile=prod*'
            }
        }

        It 'Does not throw when Get-LoggingConfig itself throws' {
            Mock Get-LoggingConfig { throw 'bad config' }
            $config = [PSCustomObject]@{}
            { Write-PWSHCertutilLog -Config $config -Level Error -CmdletName 'Test' -Message 'm' -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }
    }
}
