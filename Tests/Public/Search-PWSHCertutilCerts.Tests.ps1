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
        "restrict": { "search": "{DYNAMIC}" },
        "out":      { "search": ["RequestID","CommonName","RequesterName"] }
      },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": {
          "RequestID": "RequestID",
          "CommonName": "CommonName",
          "RequesterName": "RequesterName"
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
    $emptyCsv    = @('"RequestID","CommonName","RequesterName"')
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Search-PWSHCertutilCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession      { $fakeSession }
        Mock -ModuleName Posh-Certutil Get-CACulture      { 'en-US' }
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { $emptyCsv }
    }

    It 'Uses GeneralFlags=0 as restrict when no filters are supplied' {
        Search-PWSHCertutilCerts -Profile 'test-profile' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -eq 'GeneralFlags=0' } -Times 1
    }

    It 'Includes Disposition=20 for -Type Issued' {
        Search-PWSHCertutilCerts -Profile 'test-profile' -Type Issued | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*Disposition=20*' } -Times 1
    }

    It 'Includes Disposition=21 for -Type Revoked' {
        Search-PWSHCertutilCerts -Profile 'test-profile' -Type Revoked | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*Disposition=21*' } -Times 1
    }

    It 'Joins multiple -Requester values with pipe (OR)' {
        Search-PWSHCertutilCerts -Profile 'test-profile' -Requester 'CORP\user1','CORP\user2' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*RequesterName=CORP\user1|RequesterName=CORP\user2*' } -Times 1
    }

    It 'Includes both Disposition and Subject filters when both are specified' {
        Search-PWSHCertutilCerts -Profile 'test-profile' -Type Issued -Subject 'server01' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*Disposition=20*' -and $Restrict -like '*CommonName=server01*' } -Times 1
    }

    It 'Formats -NotAfter as MM/dd/yyyy in restrict' {
        $date = [datetime]'2025-12-31'
        Search-PWSHCertutilCerts -Profile 'test-profile' -NotAfter $date | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilView `
            -ParameterFilter { $Restrict -like '*NotAfter<=12/31/2025*' } -Times 1
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        Search-PWSHCertutilCerts | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Get-CASession -Times 1
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
            { Search-PWSHCertutilCerts } | Should -Throw -ExpectedMessage '*default profile*'
        } finally {
            Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
        }
    }
}
