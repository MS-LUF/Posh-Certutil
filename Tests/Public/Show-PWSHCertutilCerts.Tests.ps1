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
      "certutilView": { "restrict": {}, "out": {} },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": {
          "RequestID": "RequestID",
          "BinaryCertificate": "BinaryCertificate"
        }
      }
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

    $fakeSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Show-PWSHCertutilCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession { $fakeSession }
    }

    Context 'When piped a certificate object' {
        It 'Extracts Profile, CAServer, RequestID from the piped object' {
            $certObj = [PSCustomObject]@{
                Profile   = 'test-profile'
                CAServer  = 'ca01.test.local'
                RequestID = '42'
            }
            Mock Invoke-Command {
                @('"RequestID","BinaryCertificate"', '"42","MIIB..."')
            } -ModuleName Posh-Certutil
            Mock -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 {
                [PSCustomObject]@{ Subject = 'CN=test'; Issuer = 'CN=CA' }
            }
            $result = $certObj | Show-PWSHCertutilCerts
            $result.Profile  | Should -Be 'test-profile'
            $result.CAServer | Should -Be 'ca01.test.local'
        }
    }

    Context 'When RequestID is not found on the CA' {
        It 'Writes an error and returns no output' {
            Mock Invoke-Command { @('"RequestID","BinaryCertificate"') } -ModuleName Posh-Certutil
            $result = Show-PWSHCertutilCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                          -RequestID '999' -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}
