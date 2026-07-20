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

Describe 'Get-PWSHCertreqCert' -Tag Unit {

    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession { $script:FakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertreqRetrieve {
            [PSCustomObject]@{
                RequestID  = '42'
                Status     = 'Issued'
                CertBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('FAKECERT'))
                ExitCode   = 0
                RawOutput  = 'Certificate retrieved(Issued)'
            }
        }
        Mock -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 {
            [PSCustomObject]@{ Subject = 'CN=server01'; Thumbprint = 'ABCD1234' }
        }
    }

    It 'Calls Invoke-CertreqRetrieve with the correct RequestID' {
        Get-PWSHCertreqCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertreqRetrieve `
            -ParameterFilter { $RequestID -eq '42' } -Times 1
    }

    It 'Returns an object with the correct Profile, CAServer, and RequestID' {
        $result = Get-PWSHCertreqCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.Profile   | Should -Be 'test-profile'
        $result.CAServer  | Should -Be 'ca01.test.local'
        $result.RequestID | Should -Be '42'
    }

    It 'Populates Certificate when Status is Issued' {
        $result = Get-PWSHCertreqCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.Status      | Should -Be 'Issued'
        $result.Certificate | Should -Not -BeNullOrEmpty
    }

    It 'Extracts Profile, CAServer, RequestID from a piped object' {
        $pendingObj = [PSCustomObject]@{
            Profile   = 'test-profile'
            CAServer  = 'ca01.test.local'
            RequestID = '42'
        }
        $pendingObj | Get-PWSHCertreqCert
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertreqRetrieve `
            -ParameterFilter { $RequestID -eq '42' } -Times 1
    }

    It 'Does not call ConvertFrom-CertutilAsn1 when Status is Pending' {
        Mock -ModuleName Posh-Certutil Invoke-CertreqRetrieve {
            [PSCustomObject]@{
                RequestID  = '42'
                Status     = 'Pending'
                CertBase64 = $null
                ExitCode   = 0
                RawOutput  = 'Certificate request is pending'
            }
        }
        $result = Get-PWSHCertreqCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        Should -Invoke -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 -Times 0
        $result.Status      | Should -Be 'Pending'
        $result.Certificate | Should -BeNullOrEmpty
    }

    It 'Writes an error when Invoke-CertreqRetrieve throws' {
        Mock -ModuleName Posh-Certutil Invoke-CertreqRetrieve { throw 'certreq retrieve failed' }
        { Get-PWSHCertreqCert -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42' `
              -ErrorAction Stop } | Should -Throw
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        $result = Get-PWSHCertreqCert -CAFqdn 'ca01.test.local' -RequestID '42'
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
            { Get-PWSHCertreqCert -CAFqdn 'ca01.test.local' -RequestID '42' -ErrorAction Stop } |
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
