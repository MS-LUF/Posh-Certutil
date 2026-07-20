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
      "cas": [
        { "fqdn": "ca01.test.local", "displayName": "CA01" },
        { "fqdn": "ca02.test.local", "displayName": "CA02" }
      ],
      "certutilView": {
        "restrict": { "issuedCerts": "GeneralFlags=0,Disposition=20" },
        "out":      { "issuedCerts": ["RequestID","CommonName"] }
      },
      "syncState": {
        "lastSync": "2026-01-01T00:00:00Z",
        "fieldNameMap": { "RequestID": "RequestID", "CommonName": "CommonName" }
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

    $fakeCsvOutput = @('"RequestID","CommonName"','"1","server01.corp.local"')
    $fakeSession   = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Get-PWSHCertutilIssuedCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession     { $fakeSession }
        Mock -ModuleName Posh-Certutil Get-CACulture     { 'en-US' }
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { $fakeCsvOutput }
    }

    It 'Queries all CAs in the profile when -CAFqdn is not specified' {
        Get-PWSHCertutilIssuedCerts -Profile 'test-profile' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Get-CASession -Times 2
    }

    It 'Queries only the specified CA when -CAFqdn is provided' {
        Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' | Out-Null
        Should -Invoke -ModuleName Posh-Certutil Get-CASession -Times 1
    }

    It 'Throws when the specified -CAFqdn is not in the profile' {
        { Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca99.test.local' } |
            Should -Throw -ExpectedMessage "*ca99.test.local*"
    }

    It 'Stamps Profile and CAServer on each returned object' {
        $result = Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local'
        $result.Profile  | Should -Be 'test-profile'
        $result.CAServer | Should -Be 'ca01.test.local'
    }

    It 'Returns empty collection when certutil returns no data rows' {
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { @('"RequestID","CommonName"') }
        $result = Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local'
        $result | Should -BeNullOrEmpty
    }

    It 'Writes an error but continues when one CA fails' {
        Mock -ModuleName Posh-Certutil Get-CASession {
            if ($CAFqdn -eq 'ca01.test.local') { throw 'connection refused' }
            $fakeSession
        }
        { Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -ErrorAction SilentlyContinue } |
            Should -Not -Throw
    }

    It 'Returns objects with canonical property names when FieldMap is applied' {
        $localizedCsv = @('"Issued Request ID","Issued Common Name"', '"1","server01.corp.local"')
        Mock -ModuleName Posh-Certutil Invoke-CertutilView { $localizedCsv }
        InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
            param($ConfigPath)
            $localizedMap = @{ 'Issued Request ID' = 'RequestID'; 'Issued Common Name' = 'CommonName' }
            $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            $json.profiles.'test-profile'.syncState.fieldNameMap |
                Add-Member -MemberType NoteProperty -Name 'Issued Request ID'  -Value 'RequestID'  -Force
            $json.profiles.'test-profile'.syncState.fieldNameMap |
                Add-Member -MemberType NoteProperty -Name 'Issued Common Name' -Value 'CommonName' -Force
            $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
            $script:ConfigPath = $ConfigPath
        }
        $result = Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local'
        $result.RequestID  | Should -Be '1'
        $result.CommonName | Should -Be 'server01.corp.local'
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        $result = Get-PWSHCertutilIssuedCerts -CAFqdn 'ca01.test.local'
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
            { Get-PWSHCertutilIssuedCerts } | Should -Throw -ExpectedMessage '*default profile*'
        } finally {
            Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
        }
    }

    It '-Profile is a dynamic parameter that offers tab completion for configured profiles' {
        $line    = 'Get-PWSHCertutilIssuedCerts -Profile '
        $results = TabExpansion2 -inputScript $line -cursorColumn $line.Length
        $results.CompletionMatches.CompletionText | Should -Contain 'test-profile'
    }

    It 'Rejects an unknown -Profile value before it ever reaches Resolve-ProfileName' {
        { Get-PWSHCertutilIssuedCerts -Profile 'does-not-exist' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*ValidateSet*'
    }

    It 'Returns NotBefore/NotAfter as DateTime, not strings, using the CA culture' {
        Mock -ModuleName Posh-Certutil Invoke-CertutilView {
            @('"RequestID","CommonName","NotBefore","NotAfter"',
              '"1","server01.corp.local","1/1/2025 12:00 AM","1/1/2026 12:00 AM"')
        }
        $result = Get-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local'
        $result.NotBefore | Should -BeOfType [datetime]
        $result.NotAfter  | Should -BeOfType [datetime]
        Should -Invoke -ModuleName Posh-Certutil Get-CACulture -Times 1
    }
}
