@{
    ModuleVersion     = '0.5.5'
    GUID              = 'c3d4e5f6-a1b2-4321-8765-0987654321ab'
    Author            = 'Lucas CUEFF'
    CompanyName       = 'Lucas-Cueff.com'
    Copyright         = '(c) Lucas CUEFF. All rights reserved.'
    Description       = 'PowerShell certutil.exe wrapper using remote PowerShell to run and aggregate certutil output on multiple ADCS Certificate Authorities.'
    PowerShellVersion = '5.1'
    RootModule        = 'Posh-Certutil.psm1'
    FunctionsToExport = @(
        'Get-PWSHCertutilConfig'
        'Set-PWSHCertutilConfig'
        'Get-PWSHCertutilIssuedCerts'
        'Get-PWSHCertutilRevokedCerts'
        'Get-PWSHCertutilShortTermExpiringCerts'
        'Get-PWSHCertutilCertStatus'
        'Search-PWSHCertutilCerts'
        'Show-PWSHCertutilCerts'
        'Revoke-PWSHCertutilIssuedCerts'
        'Publish-PWSHCertutilCACrl'
        'Sync-PWSHCertutilCASchema'
        'Submit-PWSHCertreqCSR'
        'Get-PWSHCertreqCert'
        'Approve-PWSHCertutilPendingCert'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('PKI', 'ADCS', 'Certificate', 'CA', 'Certutil', 'Windows')
            ProjectUri = ''
        }
    }
}
