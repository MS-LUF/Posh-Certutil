BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force

    $testJson = @'
{
  "version": "1.0",
  "profiles": {
    "prod-pki": {
      "description": "Production",
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [{ "fqdn": "ca01.corp.local", "displayName": "CA01" }],
      "certutilView": {
        "restrict": { "issuedCerts": "GeneralFlags=0" },
        "out": { "issuedCerts": ["RequestID"] }
      }
    },
    "lab": {
      "description": "Lab",
      "remoting": { "useTls": false, "port": 5985, "maxSessionsPerCA": 1 },
      "cas": [{ "fqdn": "ca-lab.lab.local", "displayName": "Lab CA" }],
      "certutilView": {
        "restrict": { "issuedCerts": "GeneralFlags=0" },
        "out": { "issuedCerts": ["RequestID"] }
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
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Get-PWSHCertutilConfig' -Tag Unit {
    Context 'When no -Profile is specified' {
        It 'Returns all profiles' {
            $result = Get-PWSHCertutilConfig
            $result | Should -HaveCount 2
            $result.Profile | Should -Contain 'prod-pki'
            $result.Profile | Should -Contain 'lab'
        }
    }

    Context 'When a valid -Profile is specified' {
        It 'Returns only that profile' {
            $result = Get-PWSHCertutilConfig -Profile 'prod-pki'
            $result.Profile | Should -Be 'prod-pki'
            $result.Config.description | Should -Be 'Production'
        }
    }

    Context 'When an invalid -Profile is specified' {
        It 'Throws with available profile names in the error' {
            { Get-PWSHCertutilConfig -Profile 'nonexistent' } |
                Should -Throw -ExpectedMessage '*prod-pki*'
        }
    }
}
