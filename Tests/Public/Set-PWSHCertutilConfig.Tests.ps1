BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

AfterAll {
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Set-PWSHCertutilConfig' -Tag Unit {
    BeforeEach {
        $tempConfig = [IO.Path]::GetTempFileName()
        '{"version":"1.0","profiles":{}}' | Set-Content -Path $tempConfig -Encoding UTF8
        InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $tempConfig } {
            param($ConfigPath)
            $script:ConfigPath = $ConfigPath
        }
    }

    AfterEach {
        Remove-Item -Path $tempConfig -ErrorAction SilentlyContinue
        InModuleScope Posh-Certutil {
            $script:ConfigPath = Join-Path $script:ModuleRoot 'Config\Posh-Certutil.json'
        }
    }

    It 'Writes a new profile with correct TLS settings' {
        Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca01.corp.local' -UseTls $true
        $saved = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        $saved.profiles.test.remoting.useTls | Should -Be $true
        $saved.profiles.test.remoting.port   | Should -Be 5986
    }

    It 'Defaults port to 5985 when UseTls is false' {
        Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca01.corp.local' -UseTls $false
        $saved = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        $saved.profiles.test.remoting.port | Should -Be 5985
    }

    It 'Writes all CAs to the cas array' {
        Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca01.corp.local','ca02.corp.local'
        $saved = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        $saved.profiles.test.cas | Should -HaveCount 2
    }

    It 'Updates an existing profile without duplicating it' {
        Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca01.corp.local'
        Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca02.corp.local'
        $saved = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        ($saved.profiles.PSObject.Properties | Where-Object Name -eq 'test') | Should -HaveCount 1
        $saved.profiles.test.cas[0].fqdn | Should -Be 'ca02.corp.local'
    }

    It 'Does not write to disk when -WhatIf is used' {
        Set-PWSHCertutilConfig -Profile 'whatiftest' -CAFqdn 'ca01.corp.local' -WhatIf
        $saved = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        $saved.profiles.PSObject.Properties.Name | Should -Not -Contain 'whatiftest'
    }

    It 'Returns the saved profile object' {
        $result = Set-PWSHCertutilConfig -Profile 'test' -CAFqdn 'ca01.corp.local'
        $result.Profile | Should -Be 'test'
    }
}
