BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force

    $testJson = @'
{
  "version": "1.0",
  "profiles": {
    "test-profile": {
      "description": "Test",
      "remoting": { "useTls": true, "port": 5986, "maxSessionsPerCA": 2 },
      "cas": [
        { "fqdn": "ca01.test.local", "displayName": "CA01" },
        { "fqdn": "ca02.test.local", "displayName": "CA02" }
      ],
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

    $fakeSession   = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
    $fakeCrlResult = [PSCustomObject]@{
        PublishOutput = 'CertUtil: -crl command completed successfully.'
        FileName      = 'corp-ca.crl'
        LastWriteTime = [datetime]::UtcNow
        CrlBase64     = [Convert]::ToBase64String([byte[]](0x30, 0x82))
    }
}

AfterAll {
    Remove-Item -Path $script:TestConfigPath -ErrorAction SilentlyContinue
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Publish-PWSHCertutilCACrl' -Tag Unit {
    BeforeEach {
        Mock -ModuleName Posh-Certutil Get-CASession          { $fakeSession }
        Mock -ModuleName Posh-Certutil Invoke-CertutilCrl     { $fakeCrlResult }
        Mock -ModuleName Posh-Certutil ConvertFrom-CertutilAsn1 {
            [PSCustomObject]@{ RawDump = 'decoded'; CrlBase64 = $CrlBase64 }
        }
    }

    It 'Calls Invoke-CertutilCrl once per CA when no -CAFqdn is specified' {
        Publish-PWSHCertutilCACrl -Profile 'test-profile' -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilCrl -Times 2
    }

    It 'Calls Invoke-CertutilCrl once when -CAFqdn is specified' {
        Publish-PWSHCertutilCACrl -Profile 'test-profile' -CAFqdn 'ca01.test.local' -Confirm:$false
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilCrl -Times 1
    }

    It 'Does not call Invoke-CertutilCrl when -WhatIf is used' {
        Publish-PWSHCertutilCACrl -Profile 'test-profile' -WhatIf
        Should -Invoke -ModuleName Posh-Certutil Invoke-CertutilCrl -Times 0
    }

    It 'Returns an object with Profile, CAServer, FileName, and CRLDecoded' {
        $result = Publish-PWSHCertutilCACrl -Profile 'test-profile' -CAFqdn 'ca01.test.local' -Confirm:$false
        $result.Profile    | Should -Be 'test-profile'
        $result.CAServer   | Should -Be 'ca01.test.local'
        $result.FileName   | Should -Be 'corp-ca.crl'
        $result.CRLDecoded | Should -Not -BeNullOrEmpty
    }

    It 'Throws when -CAFqdn is not in the profile' {
        { Publish-PWSHCertutilCACrl -Profile 'test-profile' -CAFqdn 'ca99.test.local' -Confirm:$false } |
            Should -Throw -ExpectedMessage '*ca99.test.local*'
    }
}
