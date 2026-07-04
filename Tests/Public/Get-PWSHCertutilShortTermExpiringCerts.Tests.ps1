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
      "certutilView": {
        "restrict": { "expiringCerts": "GeneralFlags=0,Disposition=20,NotAfter>={TODAY},NotAfter<={EXPIRE_DATE}" },
        "out":      { "expiringCerts": ["RequestID","CommonName","NotAfter"] }
      },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": {
          "RequestID": "RequestID",
          "CommonName": "CommonName",
          "NotAfter": "NotAfter"
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

Describe 'Get-PWSHCertutilShortTermExpiringCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession      { $fakeSession }
        Mock -ModuleName Posh-Certutil Get-CALocalDate    { @{ Today = '01/01/2026'; ExpireDate = '01/31/2026' } }
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { @('"RequestID","CommonName","NotAfter"') }
    }

    It 'Calls Get-CALocalDate with Days=30 by default' {
        Get-PWSHCertutilShortTermExpiringCerts -Profile 'test-profile' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Get-CALocalDate `
            -ParameterFilter { $Days -eq 30 } -Times 1
    }

    It 'Passes both CA-side dates into the restrict string' {
        Get-PWSHCertutilShortTermExpiringCerts -Profile 'test-profile' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*01/01/2026*' -and $Restrict -like '*01/31/2026*' } -Times 1
    }

    It 'Calls Get-CALocalDate with Days=90 when -Days 90 is specified' {
        Get-PWSHCertutilShortTermExpiringCerts -Profile 'test-profile' -Days 90 | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Get-CALocalDate `
            -ParameterFilter { $Days -eq 90 } -Times 1
    }

    It 'Rejects -Days values not in the allowed set' {
        { Get-PWSHCertutilShortTermExpiringCerts -Profile 'test-profile' -Days 45 } |
            Should -Throw
    }
}
