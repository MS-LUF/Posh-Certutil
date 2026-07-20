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

    $fakeSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Revoke-PWSHCertutilIssuedCerts' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession        { $fakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertutilRevoke {
            'CertUtil: -revoke command completed successfully.'
        }
    }

    It 'Calls Invoke-CertutilRevoke with the correct SerialNumber and Reason' {
        Revoke-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
            -SerialNumber '1A2B3C4D5E6F' -Reason 'KeyCompromise' -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilRevoke `
            -ParameterFilter { $SerialNumber -eq '1A2B3C4D5E6F' -and $Reason -eq 'KeyCompromise' } -Times 1
    }

    It 'Does not call Invoke-CertutilRevoke when -WhatIf is used' {
        Revoke-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
            -SerialNumber '1A2B3C4D5E6F' -WhatIf
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilRevoke -Times 0
    }

    It 'Extracts Profile, CAServer, SerialNumber from a piped object' {
        $certObj = [PSCustomObject]@{
            Profile      = 'test-profile'
            CAServer     = 'ca01.test.local'
            SerialNumber = '1A2B3C4D5E6F'
        }
        $certObj | Revoke-PWSHCertutilIssuedCerts -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilRevoke `
            -ParameterFilter { $SerialNumber -eq '1A2B3C4D5E6F' } -Times 1
    }

    It 'Returns a result object with Success=$true on success' {
        $result = Revoke-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
                      -SerialNumber '1A2B3C4D5E6F' -Confirm:$false
        $result.Success | Should -Be $true
    }

    It 'Writes an error when Invoke-CertutilRevoke throws' {
        Mock -ModuleName Posh-Certutil Invoke-CertutilRevoke { throw 'revoke failed' }
        { Revoke-PWSHCertutilIssuedCerts -Profile 'test-profile' -CAFqdn 'ca01.test.local' `
              -SerialNumber '1A2B3C4D5E6F' -Confirm:$false -ErrorAction Stop } |
            Should -Throw
    }

    It 'Falls back to the default profile when -Profile is omitted' {
        $result = Revoke-PWSHCertutilIssuedCerts -CAFqdn 'ca01.test.local' `
                      -SerialNumber '1A2B3C4D5E6F' -Confirm:$false
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
            { Revoke-PWSHCertutilIssuedCerts -CAFqdn 'ca01.test.local' `
                  -SerialNumber '1A2B3C4D5E6F' -Confirm:$false } |
                Should -Throw -ExpectedMessage '*default profile*'
        } finally {
            Remove-Item -Path $noDefaultPath -ErrorAction SilentlyContinue
            InModuleScope Posh-Certutil -Parameters @{ ConfigPath = $script:TestConfigPath } {
                param($ConfigPath)
                $script:ConfigPath = $ConfigPath
            }
        }
    }

    It '-Profile is a dynamic parameter that offers tab completion for configured profiles (Direct set)' {
        $line    = 'Revoke-PWSHCertutilIssuedCerts -CAFqdn ca01.test.local -Profile '
        $results = TabExpansion2 -inputScript $line -cursorColumn $line.Length
        $results.CompletionMatches.CompletionText | Should -Contain 'test-profile'
    }

    It 'Rejects an unknown -Profile value in the Direct parameter set' {
        { Revoke-PWSHCertutilIssuedCerts -Profile 'does-not-exist' -CAFqdn 'ca01.test.local' `
              -SerialNumber '1A2B3C4D5E6F' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*ValidateSet*'
    }
}
