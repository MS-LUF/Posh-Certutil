# Posh-Certutil

## Description
**Version 0.5.9**

A Windows PowerShell module that wraps `certutil.exe` and `certreq.exe` using PowerShell Remoting (WinRM) to execute commands locally on each CA server and aggregate the results as typed PowerShell objects.

(c) 2026 #lucas-cueff.com Distributed under [Artistic Licence 2.0](https://opensource.org/licenses/artistic-license-2.0).

---

## install from PowerShell Gallery repository
You can easily install it from powershell gallery repository
https://www.powershellgallery.com/packages/POSH-Certutil/
using a simple powershell command and an internet access :-) 
```
	Install-Module -Name POSH-Certutil
```

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+ on Windows
- WinRM access to each CA server (TLS on port 5986 or plain-text on port 5985)
- `certutil.exe` and `certreq.exe` present on each CA server (standard on all Windows Server ADCS roles)

---

## Installation

Import the module directly from the repository root:

```powershell
Import-Module .\Posh-Certutil.psd1
```

---

## Quick start

### 1 — Create a profile

```powershell
Set-PWSHCertutilConfig -Profile 'prod-pki' `
    -CAFqdn 'ca01.corp.local', 'ca02.corp.local' `
    -DisplayName 'Issuing CA 01', 'Issuing CA 02' `
    -UseTls $true -Description 'Production PKI'
```

### 2 — (Optional) Mark the profile as default

```powershell
Set-PWSHCertutilConfig -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -DefaultProfile $true
```

Once a profile is marked default, `-Profile` becomes optional on every other cmdlet — omit it and the
default profile is used. Only one profile can be default at a time; marking a new one clears the flag
on the previous default. Calling a cmdlet without `-Profile` when no default is configured throws.

`-Profile` also tab-completes: press Tab after `-Profile ` on any cmdlet (except `Set-PWSHCertutilConfig`,
which must accept brand-new names) to see the profiles currently defined in `Posh-Certutil.json`, and
an unknown name is rejected immediately instead of failing deep inside the cmdlet.

### 3 — Validate the schema against your CAs

```powershell
Sync-PWSHCertutilCASchema -Profile 'prod-pki' -UpdateConfig
```

This discovers the actual database column names on each CA and removes any invalid field names from the profile config. Run this once after pointing the module at a new environment.

### 4 — Query certificates

```powershell
# All issued certificates across the profile
Get-PWSHCertutilIssuedCerts -Profile 'prod-pki'

# Certificates expiring in the next 60 days
Get-PWSHCertutilShortTermExpiringCerts -Profile 'prod-pki' -Days 60

# Search by requester or subject
Search-PWSHCertutilCerts -Profile 'prod-pki' -CommonName 'server01*' -Type Issued

# -Profile can be omitted once a default profile is configured (step 2)
Get-PWSHCertutilIssuedCerts
```

### 5 — Submit and retrieve a certificate request

```powershell
# Submit a CSR — returns immediately if auto-issued, or Status=Pending for manual approval
$req = Submit-PWSHCertreqCSR -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' `
           -CSRPath 'C:\requests\server01.req' -CertificateTemplate 'WebServer'

# If pending: approve as CA manager, then retrieve
$req | Approve-PWSHCertutilPendingCert -Confirm:$false
$req | Get-PWSHCertreqCert -OutputCertPath 'C:\certs\server01.cer'
```

### 6 — Revoke a certificate

```powershell
Get-PWSHCertutilIssuedCerts -Profile 'prod-pki' |
    Where-Object CommonName -eq 'server01.corp.local' |
    Revoke-PWSHCertutilIssuedCerts -Reason KeyCompromise
```

---

## Cmdlet reference

### Configuration

| Cmdlet | Description |
|---|---|
| `Set-PWSHCertutilConfig` | Create or update a profile in `Posh-Certutil.json`; `-DefaultProfile $true` marks it as the default used when `-Profile` is omitted elsewhere |
| `Get-PWSHCertutilConfig` | Read the config and return profiles as objects |
| `Sync-PWSHCertutilCASchema` | Discover CA database schema; optionally remove invalid field names from the profile config |

### Certificate queries

| Cmdlet | Alias | Description |
|---|---|---|
| `Get-PWSHCertutilIssuedCerts` | `Get-PWSHCertutilIssuedCert` | Return all issued certificates for a profile |
| `Get-PWSHCertutilRevokedCerts` | `Get-PWSHCertutilRevokedCert` | Return all revoked certificates for a profile |
| `Get-PWSHCertutilShortTermExpiringCerts` | `Get-PWSHCertutilShortTermExpiringCert` | Return certificates expiring in the next 30 / 60 / 90 / 120 days |
| `Search-PWSHCertutilCerts` | `Search-PWSHCertutilCert` | Search issued and/or revoked certificates by requester, subject, date, etc. |
| `Get-PWSHCertutilCertStatus` | — | Return the disposition of a certificate (Issued / Revoked) with CRL info and decoded certificate |
| `Show-PWSHCertutilCerts` | `Show-PWSHCertutilCert` | Return the ASN.1-decoded certificate as a PowerShell object |

### Certificate request lifecycle

| Cmdlet | Description |
|---|---|
| `Submit-PWSHCertreqCSR` | Submit a local CSR to a CA via `certreq -submit`; returns Status=Issued or Status=Pending |
| `Get-PWSHCertreqCert` | Retrieve an issued certificate by request ID via `certreq -retrieve` |
| `Approve-PWSHCertutilPendingCert` | Approve a pending request on the CA via `certutil -resubmit` (CA manager action) |

### Certificate management

| Cmdlet | Alias | Description |
|---|---|---|
| `Revoke-PWSHCertutilIssuedCerts` | `Revoke-PWSHCertutilIssuedCert` | Revoke a certificate on the CA where it was issued |
| `Publish-PWSHCertutilCACrl` | — | Publish a new CRL on one or all CAs in a profile; return the decoded CRL |

All query cmdlets return objects with at minimum `Profile` and `CAServer` properties. Pipeline-aware cmdlets (`Revoke-`, `Show-`, `Get-PWSHCertutilCertStatus`, `Get-PWSHCertreqCert`, `Approve-`) accept the output of query cmdlets directly.

Every date/time output property (`NotBefore`, `NotAfter`, `RevokedEffectiveWhen`, `Get-PWSHCertutilCertStatus`'s `CRLInfo.RevokedWhen`, `Get-PWSHCertutilConfig`'s `Config.syncState.lastSync`) is a real `[datetime]`, not a string — safe to use directly with `-lt`/`-gt`/`.AddDays()` etc. without parsing.

A handful of cmdlet nouns predate the PowerShell guideline that nouns should be singular; each of
those keeps its historical plural name as the canonical cmdlet and gets a singular-noun alias (see
the "Alias" columns above) — e.g. `Get-PWSHCertutilIssuedCert -Profile 'prod-pki'` works exactly
like `Get-PWSHCertutilIssuedCerts -Profile 'prod-pki'`.

`-Profile` is optional on every cmdlet except `Set-PWSHCertutilConfig`. When omitted, the profile marked `-DefaultProfile $true` is used; if no profile is marked default, the cmdlet throws.

---

## Documentation

| Document | Contents |
|---|---|
| [Docs/Architecture.md](Docs/Architecture.md) | Module structure, data pipeline, certreq workflow, session management, output object contract, error handling |
| [Docs/ConfigSchema.md](Docs/ConfigSchema.md) | Full JSON configuration schema reference, restrict/out field rules, disposition values |
| [Docs/SessionManagement.md](Docs/SessionManagement.md) | WinRM session pool design, liveness probe, throttling, TLS configuration |
| [Docs/TestPlan.md](Docs/TestPlan.md) | Pester coverage matrix for every public cmdlet and private helper |

---

## External references

- **[Microsoft documentation](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)** — `certutil` and `certreq` command reference (load via Microsoft MCP server for the latest version)
- **[sysadmins.lv — disposition values](https://www.sysadmins.lv/retired-msft-blogs/pki/disposition-values-for-certutil-ndashview-ndashrestrict-and-some-creative-samples.aspx)** — `certutil -view -restrict` / `-out` disposition values and restrict syntax
- **[sysadmins.lv — expiring certificates](https://www.sysadmins.lv/retired-msft-blogs/pki/how-to-determine-all-certificates-that-will-expire-within-30-days.aspx)** — expiring certificate queries
- **[gradenegger.eu — certificate revocation](https://www.gradenegger.eu/en/revocation-of-an-issued-certificate/)** — CRL publishing and revocation
- **[gradenegger.eu — CRL publishing](https://www.gradenegger.eu/en/publish-a-certificate-revocation-list-on-an-active-directory-revocation-list-distribution-point/)** — publishing CRLs to ADCS distribution points
- **[gradenegger.eu — certificate requests](https://www.gradenegger.eu/en/send-a-manually-created-certificate-request-to-a-certification-body/)** — `certreq -submit` / `-retrieve`, manual approval workflow
- **[gradenegger.eu — extended DB queries](https://www.gradenegger.eu/en/extended-queries-against-the-certification-bodies-database/)** — advanced `certutil -view` queries

---

## Running the tests

```powershell
Import-Module Pester -MinimumVersion 5.3
Invoke-Pester -Path .\Tests -Tag Unit -Output Detailed
```

Unit tests require no CA connection. Integration tests (tagged `Integration`) require a reachable CA and are excluded by default.
