function ConvertFrom-CertutilAsn1 {
    [CmdletBinding(DefaultParameterSetName = 'Certificate')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate,

        [Parameter(Mandatory, ParameterSetName = 'CertBase64')]
        [string] $CertBase64,

        [Parameter(Mandatory, ParameterSetName = 'CrlBase64')]
        [string] $CrlBase64
    )

    switch ($PSCmdlet.ParameterSetName) {
        'CertBase64' {
            $bytes = [Convert]::FromBase64String($CertBase64)
            $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
            ConvertFrom-CertutilAsn1 -Certificate $cert
        }
        'Certificate' {
            [PSCustomObject]@{
                Subject      = $Certificate.Subject
                Issuer       = $Certificate.Issuer
                SerialNumber = $Certificate.SerialNumber
                NotBefore    = $Certificate.NotBefore
                NotAfter     = $Certificate.NotAfter
                Thumbprint   = $Certificate.Thumbprint
                Extensions   = $Certificate.Extensions | ForEach-Object {
                    [PSCustomObject]@{
                        OID          = $_.Oid.Value
                        FriendlyName = $_.Oid.FriendlyName
                        Value        = $_.Format($false)
                    }
                }
                RawCert      = $Certificate
            }
        }
        'CrlBase64' {
            # CRL ASN.1 decoded via certutil -dump (PS 5.1 compatible, no X509CRL2 class needed)
            $tempCrl = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$([IO.Path]::GetRandomFileName()).crl")
            try {
                [IO.File]::WriteAllBytes($tempCrl, [Convert]::FromBase64String($CrlBase64))
                $dump = & certutil.exe -dump $tempCrl 2>&1
                if ($dump -match 'CertUtil:.*command FAILED') {
                    throw "certutil -dump failed on CRL: $($dump -join ' ')"
                }
                [PSCustomObject]@{
                    RawDump   = $dump -join "`n"
                    CrlBase64 = $CrlBase64
                }
            } finally {
                Remove-Item -Path $tempCrl -ErrorAction SilentlyContinue
            }
        }
    }
}
