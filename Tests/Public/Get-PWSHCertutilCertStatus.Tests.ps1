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
      "certutilView": { "restrict": {}, "out": {} },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": {
          "RequestID": "RequestID",
          "Disposition": "Disposition",
          "RequesterName": "RequesterName",
          "CommonName": "CommonName",
          "NotBefore": "NotBefore",
          "NotAfter": "NotAfter",
          "SerialNumber": "SerialNumber",
          "BinaryCertificate": "BinaryCertificate",
          "RevokedReason": "RevokedReason",
          "RevokedEffectiveWhen": "RevokedEffectiveWhen"
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

Describe 'Get-PWSHCertutilCertStatus' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession { $fakeSession }
        Mock -ModuleName Posh-Certutil Get-CACulture { 'en-US' }
        Mock -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 { $null }
    }

    It 'Returns Status = Issued when Disposition is 20' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"42","20","CORP\user1","server01","01/01/2025","12/31/2025","1A2B","","",""')
        } -ModuleName Posh-Certutil
        $result = Get-PWSHCertutilCertStatus -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.Status | Should -Be 'Issued'
    }

    It 'Returns Status = Revoked when Disposition is 21' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"42","21","CORP\user1","server01","01/01/2025","12/31/2025","1A2B","","1","06/01/2025"')
        } -ModuleName Posh-Certutil
        $result = Get-PWSHCertutilCertStatus -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.Status | Should -Be 'Revoked'
        $result.CRLInfo.RevokedReason | Should -Be '1'
    }

    It 'Returns CRLInfo.RevokedWhen as a DateTime, not a string' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"42","21","CORP\user1","server01","01/01/2025","12/31/2025","1A2B","","1","06/01/2025"')
        } -ModuleName Posh-Certutil
        $result = Get-PWSHCertutilCertStatus -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.CRLInfo.RevokedWhen | Should -BeOfType [datetime]
        $result.CRLInfo.RevokedWhen | Should -Be ([datetime]'06/01/2025')
    }

    It 'Returns unknown status for unrecognised disposition' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"42","30","","","","","","","",""')
        } -ModuleName Posh-Certutil
        $result = Get-PWSHCertutilCertStatus -Profile 'test-profile' -CAFqdn 'ca01.test.local' -RequestID '42'
        $result.Status | Should -BeLike 'Unknown*'
    }

    It 'Accepts piped input and extracts Profile/CAServer/RequestID' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"99","20","","server01","","","","","",""')
        } -ModuleName Posh-Certutil
        $certObj = [PSCustomObject]@{ Profile = 'test-profile'; CAServer = 'ca01.test.local'; RequestID = '99' }
        $result  = $certObj | Get-PWSHCertutilCertStatus
        $result.RequestID | Should -Be '99'
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        Mock Invoke-Command {
            @('"RequestID","Disposition","RequesterName","CommonName","NotBefore","NotAfter","SerialNumber","BinaryCertificate","RevokedReason","RevokedEffectiveWhen"',
              '"42","20","CORP\user1","server01","01/01/2025","12/31/2025","1A2B","","",""')
        } -ModuleName Posh-Certutil
        $result = Get-PWSHCertutilCertStatus -CAFqdn 'ca01.test.local' -RequestID '42'
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
            { Get-PWSHCertutilCertStatus -CAFqdn 'ca01.test.local' -RequestID '42' -ErrorAction Stop } |
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
