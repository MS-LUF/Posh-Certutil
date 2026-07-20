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
      "certutilView": {
        "restrict": { "revokedCerts": "Disposition=21" },
        "out":      { "revokedCerts": ["RequestID","CommonName","RevokedReason"] }
      },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": {
          "RequestID": "RequestID",
          "CommonName": "CommonName",
          "RevokedReason": "RevokedReason"
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
    $fakeCsvOutput = @('"RequestID","CommonName","RevokedReason"','"5","server01.corp.local","1"')
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Get-PWSHCertutilRevokedCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession      { $fakeSession }
        Mock -ModuleName Posh-Certutil Get-CACulture      { 'en-US' }
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { $fakeCsvOutput }
    }

    It 'Uses the revokedCerts restrict value from the profile' {
        Get-PWSHCertutilRevokedCerts -Profile 'test-profile' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*Disposition=21*' } -Times 1
    }

    It 'Stamps Profile and CAServer on returned objects' {
        $result = Get-PWSHCertutilRevokedCerts -Profile 'test-profile'
        $result.Profile  | Should -Be 'test-profile'
        $result.CAServer | Should -Be 'ca01.test.local'
    }

    It 'Throws when -CAFqdn is not in the profile' {
        { Get-PWSHCertutilRevokedCerts -Profile 'test-profile' -CAFqdn 'ca99.test.local' } |
            Should -Throw -ExpectedMessage '*ca99.test.local*'
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        $result = Get-PWSHCertutilRevokedCerts
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
            { Get-PWSHCertutilRevokedCerts } | Should -Throw -ExpectedMessage '*default profile*'
        } finally {
            Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
        }
    }
}
