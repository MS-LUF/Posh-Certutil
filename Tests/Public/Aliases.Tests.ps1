BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

AfterAll {
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

Describe 'Cmdlet aliases' -Tag Unit {
    It "Registers 'Get-PWSHCertutilIssuedCert' as an alias for 'Get-PWSHCertutilIssuedCerts'" {
        $cmd = Get-Command -Name 'Get-PWSHCertutilIssuedCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Get-PWSHCertutilIssuedCerts'
    }

    It "Registers 'Get-PWSHCertutilRevokedCert' as an alias for 'Get-PWSHCertutilRevokedCerts'" {
        $cmd = Get-Command -Name 'Get-PWSHCertutilRevokedCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Get-PWSHCertutilRevokedCerts'
    }

    It "Registers 'Get-PWSHCertutilShortTermExpiringCert' as an alias for 'Get-PWSHCertutilShortTermExpiringCerts'" {
        $cmd = Get-Command -Name 'Get-PWSHCertutilShortTermExpiringCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Get-PWSHCertutilShortTermExpiringCerts'
    }

    It "Registers 'Revoke-PWSHCertutilIssuedCert' as an alias for 'Revoke-PWSHCertutilIssuedCerts'" {
        $cmd = Get-Command -Name 'Revoke-PWSHCertutilIssuedCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Revoke-PWSHCertutilIssuedCerts'
    }

    It "Registers 'Search-PWSHCertutilCert' as an alias for 'Search-PWSHCertutilCerts'" {
        $cmd = Get-Command -Name 'Search-PWSHCertutilCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Search-PWSHCertutilCerts'
    }

    It "Registers 'Show-PWSHCertutilCert' as an alias for 'Show-PWSHCertutilCerts'" {
        $cmd = Get-Command -Name 'Show-PWSHCertutilCert' -Module Posh-Certutil
        $cmd.CommandType | Should -Be 'Alias'
        $cmd.ResolvedCommandName | Should -Be 'Show-PWSHCertutilCerts'
    }

    It 'Exports exactly the expected alias set — no more, no fewer' {
        $expected = @(
            'Get-PWSHCertutilIssuedCert'
            'Get-PWSHCertutilRevokedCert'
            'Get-PWSHCertutilShortTermExpiringCert'
            'Revoke-PWSHCertutilIssuedCert'
            'Search-PWSHCertutilCert'
            'Show-PWSHCertutilCert'
        )
        $exported = (Get-Module Posh-Certutil).ExportedAliases.Keys | Sort-Object
        $exported | Should -Be ($expected | Sort-Object)
    }
}
