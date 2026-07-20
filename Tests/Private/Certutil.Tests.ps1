BeforeDiscovery {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

BeforeAll {
    Import-Module (Resolve-Path "$PSScriptRoot\..\..\Posh-Certutil.psd1") -Force
}

AfterAll {
    Remove-Module Posh-Certutil -ErrorAction SilentlyContinue
}

InModuleScope Posh-Certutil {

    Describe 'ConvertFrom-CertutilCsv' -Tag Unit {
        It 'Returns empty when input has only a header row' {
            $result = ConvertFrom-CertutilCsv -RawOutput @('"RequestID","CommonName"')
            $result | Should -BeNullOrEmpty
        }

        It 'Returns correct objects when header + data rows are present' {
            $raw = @(
                '"RequestID","CommonName"',
                '"1","server01.corp.local"',
                '"2","server02.corp.local"',
                'CertUtil: -view command completed successfully.',
                ''
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw
            $result | Should -HaveCount 2
            $result[0].RequestID | Should -Be '1'
            $result[1].CommonName | Should -Be 'server02.corp.local'
        }

        It 'Returns empty when input is an empty collection' {
            $result = ConvertFrom-CertutilCsv -RawOutput @()
            $result | Should -BeNullOrEmpty
        }

        It 'Excludes certutil status and blank lines from output' {
            $raw = @(
                '"RequestID","CommonName"',
                '"1","test.corp.local"',
                '',
                'CertUtil: -view command completed successfully.',
                '1 Rows'
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw
            $result | Should -HaveCount 1
        }

        It 'Renames localized column headers to canonical names when FieldMap is provided' {
            $raw = @(
                '"Issued Request ID","Issued Common Name"',
                '"5","server01.corp.local"'
            )
            $map    = @{ 'Issued Request ID' = 'RequestID'; 'Issued Common Name' = 'CommonName' }
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -FieldMap $map
            $result | Should -HaveCount 1
            $result[0].RequestID  | Should -Be '5'
            $result[0].CommonName | Should -Be 'server01.corp.local'
        }

        It 'Passes through columns not present in FieldMap unchanged' {
            $raw = @(
                '"RequestID","UnmappedColumn"',
                '"1","somevalue"'
            )
            $map    = @{ 'RequestID' = 'RequestID' }
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -FieldMap $map
            $result[0].UnmappedColumn | Should -Be 'somevalue'
        }

        It 'Leaves date-shaped columns as strings when -CACulture is not supplied' {
            $raw = @(
                '"RequestID","NotBefore","NotAfter"',
                '"1","1/1/2025 12:00 AM","1/1/2026 12:00 AM"'
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw
            $result[0].NotBefore | Should -BeOfType [string]
            $result[0].NotAfter  | Should -BeOfType [string]
        }

        It 'Parses NotBefore/NotAfter/RevokedEffectiveWhen into DateTime when -CACulture is supplied' {
            $raw = @(
                '"RequestID","NotBefore","NotAfter","RevokedEffectiveWhen"',
                '"1","1/1/2025 12:00 AM","1/1/2026 12:00 AM","6/1/2025 12:00 AM"'
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -CACulture 'en-US'
            $result[0].NotBefore             | Should -BeOfType [datetime]
            $result[0].NotAfter              | Should -BeOfType [datetime]
            $result[0].RevokedEffectiveWhen  | Should -BeOfType [datetime]
            $result[0].NotBefore             | Should -Be ([datetime]'1/1/2025 12:00 AM')
        }

        It 'Parses date columns using the supplied CA culture, not the local machine culture' {
            $raw = @(
                '"RequestID","NotBefore"',
                '"1","25/12/2025 00:00:00"'
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -CACulture 'fr-FR'
            $result[0].NotBefore.Day   | Should -Be 25
            $result[0].NotBefore.Month | Should -Be 12
        }

        It 'Treats an empty date value as $null rather than throwing' {
            $raw = @(
                '"RequestID","RevokedEffectiveWhen"',
                '"1",""'
            )
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -CACulture 'en-US'
            $result[0].RevokedEffectiveWhen | Should -BeNullOrEmpty
        }

        It 'Applies date parsing after FieldMap renaming (operates on canonical names)' {
            $raw = @(
                '"Issued NotBefore"',
                '"1/1/2025 12:00 AM"'
            )
            $map    = @{ 'Issued NotBefore' = 'NotBefore' }
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -FieldMap $map -CACulture 'en-US'
            $result[0].NotBefore | Should -BeOfType [datetime]
        }

        It 'Warns and leaves the value unchanged when a date string cannot be parsed' {
            $raw = @(
                '"RequestID","NotBefore"',
                '"1","not-a-date"'
            )
            $warnings = $null
            $result = ConvertFrom-CertutilCsv -RawOutput $raw -CACulture 'en-US' -WarningVariable warnings -WarningAction SilentlyContinue
            $result[0].NotBefore | Should -Be 'not-a-date'
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Get-CACulture' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns the culture name from the CA session' {
            Mock Invoke-Command { 'fr-FR' }
            $result = Get-CACulture -Session $mockSession
            $result | Should -Be 'fr-FR'
        }

        It 'Invokes the remote command against the supplied session' {
            Mock Invoke-Command { 'en-US' }
            Get-CACulture -Session $mockSession | Out-Null
            Should -Invoke Invoke-Command -ParameterFilter {
                $Session -eq $mockSession
            } -Times 1
        }
    }

    Describe 'Get-CertutilFieldNameMap' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns a hashtable mapping localized names to canonical names' {
            Mock Invoke-Command {
                @('"Issued Request ID","Issued Common Name"')
            }
            $result = Get-CertutilFieldNameMap -Session $mockSession `
                          -CanonicalFieldNames @('RequestID', 'CommonName')
            $result['Issued Request ID'] | Should -Be 'RequestID'
            $result['Issued Common Name'] | Should -Be 'CommonName'
        }

        It 'Throws when the CA returns no CSV header' {
            Mock Invoke-Command { @('CertUtil: command completed successfully.') }
            { Get-CertutilFieldNameMap -Session $mockSession `
                  -CanonicalFieldNames @('RequestID') } |
                Should -Throw -ExpectedMessage '*no CSV header*'
        }

        It 'Throws when the column count in the header does not match the requested fields' {
            Mock Invoke-Command { @('"OnlyOneColumn"') }
            { Get-CertutilFieldNameMap -Session $mockSession `
                  -CanonicalFieldNames @('RequestID', 'CommonName') } |
                Should -Throw -ExpectedMessage '*expected 2*'
        }
    }

    Describe 'Get-CALocalDate' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns Today and ExpireDate keys from the CA' {
            Mock Invoke-Command { @{ Today = '01/01/2026'; ExpireDate = '01/31/2026' } }
            $result = Get-CALocalDate -Session $mockSession -Days 30
            $result.Today      | Should -Not -BeNullOrEmpty
            $result.ExpireDate | Should -Not -BeNullOrEmpty
        }

        It 'Passes Days as the argument to the remote scriptblock' {
            Mock Invoke-Command { @{ Today = '01/01/2026'; ExpireDate = '04/01/2026' } }
            Get-CALocalDate -Session $mockSession -Days 90
            Should -Invoke Invoke-Command -ParameterFilter {
                $ArgumentList[0] -eq 90
            } -Times 1
        }
    }

    Describe 'Add-ResultMetadata' -Tag Unit {
        It 'Stamps Profile and CAServer on a single object' {
            $obj    = [PSCustomObject]@{ RequestID = '1' }
            $result = $obj | Add-ResultMetadata -Profile 'prod-pki' -CAServer 'ca01.corp.local'
            $result.Profile  | Should -Be 'prod-pki'
            $result.CAServer | Should -Be 'ca01.corp.local'
            $result.RequestID | Should -Be '1'
        }

        It 'Stamps all objects when piped from an array' {
            $objs   = @(
                [PSCustomObject]@{ RequestID = '1' }
                [PSCustomObject]@{ RequestID = '2' }
            )
            $result = $objs | Add-ResultMetadata -Profile 'lab' -CAServer 'ca-lab.lab.local'
            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Profile | Should -Be 'lab' }
        }

        It 'Overwrites existing Profile/CAServer properties with -Force' {
            $obj    = [PSCustomObject]@{ Profile = 'old'; CAServer = 'old-ca' }
            $result = $obj | Add-ResultMetadata -Profile 'new' -CAServer 'new-ca'
            $result.Profile  | Should -Be 'new'
            $result.CAServer | Should -Be 'new-ca'
        }
    }

    Describe 'ConvertFrom-CertutilSchema' -Tag Unit {
        BeforeAll {
            $script:mockSchemaOutput = @(
                'Schema:',
                '',
                '  Columns:',
                'Column Name              Localized Name       Index  Flags   Type    MaxLength',
                '----------------------   -----------------   -----  ------  ------  ---------',
                'RequestID                Request ID          1      0x0     Long    4',
                'RawRequest               Binary Request      2      0x80    Binary  65536',
                'RequesterName            Requester Name      3      0x0     String  128',
                'CommonName               Common Name         6      0x0     String  64',
                'NotBefore                Not Before          7      0x0     Date    8',
                'NotAfter                 Not After           8      0x0     Date    8',
                'SerialNumber             Serial Number       9      0x0     String  128',
                'CertificateTemplate      Template Name       10     0x0     String  256',
                'Disposition              Disposition         11     0x0     Long    4',
                'RevokedReason            Revocation Reason   12     0x0     Long    4',
                'RevokedEffectiveWhen     Revoked When        13     0x0     Date    8',
                '',
                'CertUtil: -schema command completed successfully.'
            )
        }

        It 'Extracts all column names from certutil -schema output' {
            $result = ConvertFrom-CertutilSchema -RawOutput $script:mockSchemaOutput
            $result | Should -HaveCount 11
            $result | Should -Contain 'RequestID'
            $result | Should -Contain 'CommonName'
            $result | Should -Contain 'RevokedEffectiveWhen'
        }

        It 'Excludes schema headers, separators, and status lines' {
            $result = ConvertFrom-CertutilSchema -RawOutput $script:mockSchemaOutput
            $result | Should -Not -Contain 'Schema:'
            $result | Should -Not -Contain 'Column'
            $result | Should -Not -Contain 'CertUtil:'
        }

        It 'Returns empty for empty input' {
            $result = ConvertFrom-CertutilSchema -RawOutput @()
            $result | Should -BeNullOrEmpty
        }

        It 'Returns empty for input that is only status lines' {
            $result = ConvertFrom-CertutilSchema -RawOutput @(
                'Schema:', '', 'CertUtil: -schema command completed successfully.'
            )
            $result | Should -BeNullOrEmpty
        }
    }

    Describe 'Invoke-CertutilView' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns stdout lines when certutil succeeds' {
            Mock Invoke-Command { @('"RequestID","CommonName"', '"1","test.corp.local"') }
            $result = Invoke-CertutilView -Session $mockSession -Restrict 'Disposition=20' -Out 'RequestID,CommonName'
            $result | Should -HaveCount 2
        }

        It 'Throws when certutil stdout contains a FAILED message' {
            Mock Invoke-Command { @('CertUtil: -view command FAILED: 0x80070057 (WIN32: 87 ERROR_INVALID_PARAMETER)') }
            { Invoke-CertutilView -Session $mockSession -Restrict 'Disposition=20' -Out 'RequestID' } |
                Should -Throw -ExpectedMessage '*certutil -view failed*'
        }
    }

    Describe 'Invoke-CertutilSchema' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns stdout lines when certutil succeeds' {
            Mock Invoke-Command { @('RequestID  Request ID  1  0x0  Long  4') }
            $result = Invoke-CertutilSchema -Session $mockSession
            $result | Should -HaveCount 1
        }

        It 'Throws when certutil stdout contains a FAILED message' {
            Mock Invoke-Command { @('CertUtil: -schema command FAILED: 0x80070005 (WIN32: 5 ERROR_ACCESS_DENIED)') }
            { Invoke-CertutilSchema -Session $mockSession } |
                Should -Throw -ExpectedMessage '*certutil -schema failed*'
        }
    }

    Describe 'Invoke-CertutilRevoke' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Passes reason code 1 for KeyCompromise' {
            Mock Invoke-Command { 'CertUtil: -revoke command completed successfully.' }
            Invoke-CertutilRevoke -Session $mockSession -SerialNumber '1A2B3C4D5E6F' -Reason 'KeyCompromise'
            Should -Invoke Invoke-Command -ParameterFilter {
                $ArgumentList[1] -eq 1
            } -Times 1
        }

        It 'Passes integer reason codes directly' {
            Mock Invoke-Command { 'CertUtil: -revoke command completed successfully.' }
            Invoke-CertutilRevoke -Session $mockSession -SerialNumber '1A2B3C4D5E6F' -Reason '4'
            Should -Invoke Invoke-Command -ParameterFilter {
                $ArgumentList[1] -eq 4
            } -Times 1
        }

        It 'Throws when certutil output contains FAILED' {
            Mock Invoke-Command { 'CertUtil: -revoke command FAILED: 0x80070057' }
            { Invoke-CertutilRevoke -Session $mockSession -SerialNumber '1A2B3C4D5E6F' -Reason 'Unspecified' } |
                Should -Throw
        }

        It 'Throws for an invalid reason name' {
            { Invoke-CertutilRevoke -Session $mockSession -SerialNumber '1A2B3C4D5E6F' -Reason 'NotAReason' } |
                Should -Throw -ExpectedMessage '*Invalid revocation reason*'
        }
    }

    Describe 'Invoke-CertutilResubmit' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Passes the RequestID as an argument to certutil' {
            Mock Invoke-Command { 'CertUtil: -resubmit command completed successfully.' }
            Invoke-CertutilResubmit -Session $mockSession -RequestID '42'
            Should -Invoke Invoke-Command -ParameterFilter {
                $ArgumentList[0] -eq '42'
            } -Times 1
        }

        It 'Returns output on success' {
            Mock Invoke-Command { 'CertUtil: -resubmit command completed successfully.' }
            $result = Invoke-CertutilResubmit -Session $mockSession -RequestID '42'
            $result | Should -Match 'completed successfully'
        }

        It 'Throws when certutil output contains FAILED' {
            Mock Invoke-Command { 'CertUtil: -resubmit command FAILED: 0x80094004' }
            { Invoke-CertutilResubmit -Session $mockSession -RequestID '42' } |
                Should -Throw -ExpectedMessage '*certutil -resubmit failed*'
        }
    }

    Describe 'Invoke-CertreqSubmit' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns RequestID and Status=Issued when certreq succeeds and cert file is written' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = '5'
                    Status     = 'Issued'
                    CertBase64 = 'AAAA'
                    ExitCode   = 0
                    RawOutput  = "RequestId: 5`nCertificate retrieved(Issued)"
                }
            }
            $result = Invoke-CertreqSubmit -Session $mockSession `
                          -CSRBytes ([byte[]]@(1, 2, 3)) -CertificateTemplate 'WebServer'
            $result.RequestID | Should -Be '5'
            $result.Status    | Should -Be 'Issued'
            $result.CertBase64 | Should -Be 'AAAA'
        }

        It 'Returns Status=Pending when certreq exits 0 but no cert file is written' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = '6'
                    Status     = 'Pending'
                    CertBase64 = $null
                    ExitCode   = 0
                    RawOutput  = "RequestId: 6`nCertificate request is pending"
                }
            }
            $result = Invoke-CertreqSubmit -Session $mockSession `
                          -CSRBytes ([byte[]]@(1, 2, 3)) -CertificateTemplate 'ManualApproval'
            $result.Status    | Should -Be 'Pending'
            $result.CertBase64 | Should -BeNullOrEmpty
        }

        It 'Throws when Status is Failed (non-zero exit code)' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = $null
                    Status     = 'Failed'
                    CertBase64 = $null
                    ExitCode   = 1
                    RawOutput  = 'Certificate Request Denied'
                }
            }
            { Invoke-CertreqSubmit -Session $mockSession `
                  -CSRBytes ([byte[]]@(1, 2, 3)) -CertificateTemplate 'WebServer' } |
                Should -Throw -ExpectedMessage '*certreq -submit failed*'
        }
    }

    Describe 'Invoke-CertreqRetrieve' -Tag Unit {
        BeforeAll {
            $mockSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession
        }

        It 'Returns RequestID and Status=Issued when cert file is retrieved' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = '42'
                    Status     = 'Issued'
                    CertBase64 = 'BBBB'
                    ExitCode   = 0
                    RawOutput  = 'Certificate retrieved(Issued)'
                }
            }
            $result = Invoke-CertreqRetrieve -Session $mockSession -RequestID '42'
            $result.RequestID  | Should -Be '42'
            $result.Status     | Should -Be 'Issued'
            $result.CertBase64 | Should -Be 'BBBB'
        }

        It 'Returns Status=Pending when cert is not yet issued' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = '42'
                    Status     = 'Pending'
                    CertBase64 = $null
                    ExitCode   = 0
                    RawOutput  = 'Certificate request is pending'
                }
            }
            $result = Invoke-CertreqRetrieve -Session $mockSession -RequestID '42'
            $result.Status    | Should -Be 'Pending'
            $result.CertBase64 | Should -BeNullOrEmpty
        }

        It 'Throws when Status is Failed (non-zero exit code)' {
            Mock Invoke-Command {
                [PSCustomObject]@{
                    RequestID  = '42'
                    Status     = 'Failed'
                    CertBase64 = $null
                    ExitCode   = 1
                    RawOutput  = 'Certificate denied by policy'
                }
            }
            { Invoke-CertreqRetrieve -Session $mockSession -RequestID '42' } |
                Should -Throw -ExpectedMessage '*certreq -retrieve failed*'
        }
    }
}
