BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force

    $testJson = @'
{
  "version": "1.0",
  "profiles": {
    "test-profile": {
      "description": "Test",
      "defaultProfile": true,
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [{ "fqdn": "ca01.test.local", "displayName": "CA01" }],
      "certutilView": { "restrict": {}, "out": {} }
    }
  }
}
'@
    $script:TestConfigPath = [IO.Path]::GetTempFileName()
    Set-Content -Path $script:TestConfigPath -Value $testJson -Encoding UTF8
    InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
        param($ConfigPath)
        $script:ConfigPath = $ConfigPath
    }

    $script:FakeSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Approve-PWSHCertutilPendingCert' -Tag Unit {

    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession { $script:FakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertutilResubmit {
            'CertUtil: -resubmit command completed successfully.'
        }
    }

    It 'Calls Invoke-CertutilResubmit with the correct RequestID' {
        Approve-PWSHCertutilPendingCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
            -RequestID '42' -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilResubmit `
            -ParameterFilter { $RequestID -eq '42' } -Times 1
    }

    It 'Does not call Invoke-CertutilResubmit when -WhatIf is used' {
        Approve-PWSHCertutilPendingCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
            -RequestID '42' -WhatIf
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilResubmit -Times 0
    }

    It 'Extracts Profile, CAServer, RequestID from a piped object' {
        $pendingObj = [PSCustomObject]@{
            Profile   = 'test-profile'
            CAServer  = 'ca01.test.local'
            RequestID = '42'
        }
        $pendingObj | Approve-PWSHCertutilPendingCert -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilResubmit `
            -ParameterFilter { $RequestID -eq '42' } -Times 1
    }

    It 'Returns a result object with Success=$true on success' {
        $result = Approve-PWSHCertutilPendingCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                      -RequestID '42' -Confirm:$false
        $result.Success   | Should -Be $true
        $result.Profile   | Should -Be 'test-profile'
        $result.CAServer  | Should -Be 'ca01.test.local'
        $result.RequestID | Should -Be '42'
    }

    It 'Writes an error when Invoke-CertutilResubmit throws' {
        Mock -ModuleName Posh-Certutil Invoke-CertutilResubmit { throw 'resubmit failed' }
        { Approve-PWSHCertutilPendingCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
              -RequestID '42' -Confirm:$false -ErrorAction Stop } | Should -Throw
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        $result = Approve-PWSHCertutilPendingCert -CAFqdn 'ca01.test.local' -RequestID '42' -Confirm:$false
        $result.Profile | Should -Be 'test-profile'
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
            { Approve-PWSHCertutilPendingCert -CAFqdn 'ca01.test.local' -RequestID '42' -Confirm:$false } |
                Should -Throw -ExpectedMessage '*default profile*'
        } finally {
            Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
        }
    }
}
