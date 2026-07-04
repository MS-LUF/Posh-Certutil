BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force

    $testJson = @'
{
  "version": "1.0",
  "profiles": {
    "test-profile": {
      "description": "Test",
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

    # Temp CSR file — must exist because ValidateScript calls Test-Path
    $script:FakeCSRPath = [IO.Path]::GetTempFileName()
    Set-Content -Path $script:FakeCSRPath -Value 'FAKECSR' -Encoding ASCII
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Item -Path $script:FakeCSRPath    -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Submit-PWSHCertreqCSR' -Tag Unit {

    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession { $script:FakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertreqSubmit {
            [PSCustomObject]@{
                RequestID  = '5'
                Status     = 'Issued'
                CertBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('FAKECERT'))
                ExitCode   = 0
                RawOutput  = "RequestId: 5`nCertificate retrieved(Issued)"
            }
        }
        Mock -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 {
            [PSCustomObject]@{ Subject = 'CN=server01'; Thumbprint = 'ABCD1234' }
        }
    }

    It 'Calls Invoke-CertreqSubmit with the correct CertificateTemplate' {
        Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
            -CSRPath $script:FakeCSRPath -CertificateTemplate 'WebServer'
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertreqSubmit `
            -ParameterFilter { $CertificateTemplate -eq 'WebServer' } -Times 1
    }

    It 'Returns an object with the correct Profile, CAServer, and RequestID' {
        $result = Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                      -CSRPath $script:FakeCSRPath -CertificateTemplate 'WebServer'
        $result.Profile             | Should -Be 'test-profile'
        $result.CAServer            | Should -Be 'ca01.test.local'
        $result.RequestID           | Should -Be '5'
        $result.CertificateTemplate | Should -Be 'WebServer'
    }

    It 'Populates Certificate when Status is Issued' {
        $result = Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                      -CSRPath $script:FakeCSRPath -CertificateTemplate 'WebServer'
        $result.Status      | Should -Be 'Issued'
        $result.Certificate | Should -Not -BeNullOrEmpty
    }

    It 'Does not call ConvertFrom-CertutilAsn1 when Status is Pending' {
        Mock -ModuleName Posh-Certutil Invoke-CertreqSubmit {
            [PSCustomObject]@{
                RequestID  = '6'
                Status     = 'Pending'
                CertBase64 = $null
                ExitCode   = 0
                RawOutput  = "RequestId: 6`nCertificate request is pending"
            }
        }
        $result = Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                      -CSRPath $script:FakeCSRPath -CertificateTemplate 'ManualApproval'
        Should -Invoke -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 -Times 0
        $result.Status      | Should -Be 'Pending'
        $result.Certificate | Should -BeNullOrEmpty
        $result.RequestID   | Should -Be '6'
    }

    It 'Throws for a CA not defined in the profile' {
        { Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'unknown.test.local' `
              -CSRPath $script:FakeCSRPath -CertificateTemplate 'WebServer' -ErrorAction Stop } |
            Should -Throw
    }

    It 'Writes an error when Invoke-CertreqSubmit throws' {
        Mock -ModuleName Posh-Certutil Invoke-CertreqSubmit { throw 'certreq submit failed' }
        { Submit-PWSHCertreqCSR -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
              -CSRPath $script:FakeCSRPath -CertificateTemplate 'WebServer' -ErrorAction Stop } |
            Should -Throw
    }
}
