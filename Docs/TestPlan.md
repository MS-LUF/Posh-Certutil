# Test Plan — Posh-Certutil

## Framework and location

- Framework: **Pester 5** (minimum version 5.3)
- All test scripts: `Tests\` folder at the repository root
- Public function tests: `Tests\Public\<FunctionName>.Tests.ps1`
- Private function tests: `Tests\Private\Config.Tests.ps1`, `Session.Tests.ps1`, `Certutil.Tests.ps1`

## Test categories

Tests are tagged with:
- `Unit` — no WinRM, no CA, mocks only
- `Integration` — requires a live CA environment (tagged `Integration`, skipped in CI by default)

Run only unit tests:
```powershell
Invoke-Pester -Path .\Tests -Tag Unit
```

Run everything (requires a real CA):
```powershell
Invoke-Pester -Path .\Tests
```

---

## Coverage matrix — Public cmdlets

### `Get-PWSHCertutilConfig`

| Context | Test | Tag |
|---|---|---|
| No -Profile | Returns all profiles as objects | Unit |
| Valid -Profile | Returns the matching profile only | Unit |
| Invalid -Profile | Throws with profile list in message | Unit |
| Empty config file | Returns empty result without error | Unit |
| syncState.lastSync present | Returned as DateTime, not string | Unit |
| syncState absent | No error | Unit |

### `Set-PWSHCertutilConfig`

| Context | Test | Tag |
|---|---|---|
| New profile, TLS | Writes correct JSON structure | Unit |
| New profile, non-TLS | Port defaults to 5985 | Unit |
| Update existing profile | Overwrites without duplicating | Unit |
| Multiple CAFqdns | All CAs written to cas array | Unit |
| -WhatIf | Does not write to disk | Unit |
| Custom port | Port persisted correctly | Unit |
| New profile, no -DefaultProfile | defaultProfile defaults to $false | Unit |
| -DefaultProfile $true | defaultProfile written as $true | Unit |
| -DefaultProfile $true on a second profile | Clears defaultProfile on every other profile | Unit |
| Update without -DefaultProfile | Preserves the profile's existing defaultProfile value | Unit |

### `Get-PWSHCertutilIssuedCerts`

| Context | Test | Tag |
|---|---|---|
| Profile with 2 CAs | Calls Get-CASession twice | Unit |
| -CAFqdn filter | Calls Get-CASession once | Unit |
| CAFqdn not in profile | Throws | Unit |
| certutil returns 0 rows | Returns empty array | Unit |
| certutil returns rows | Returns objects with Profile+CAServer | Unit |
| One CA fails | Writes error, continues to next CA | Unit |
| FieldMap rename | Returns objects with canonical property names | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| -Profile tab completion | TabExpansion2 suggests configured profile names | Unit |
| -Profile invalid value | Rejected by ValidateSet before cmdlet body runs | Unit |
| NotBefore/NotAfter present | Returned as DateTime (via Get-CACulture), not string | Unit |
| Real CA query | Returns real issued certs | Integration |

### `Get-PWSHCertutilRevokedCerts`

Same structure as `Get-PWSHCertutilIssuedCerts` — uses `revokedCerts` operation key, plus the same
-Profile default-fallback and no-default-throws coverage.

### `Get-PWSHCertutilShortTermExpiringCerts`

| Context | Test | Tag |
|---|---|---|
| Default -Days 30 | Get-CALocalDate called with Days=30 | Unit |
| Restrict substitution | Both CA-side Today and ExpireDate appear in restrict | Unit |
| -Days 90 | Get-CALocalDate called with Days=90 | Unit |
| Invalid -Days value | Parameter validation rejects it | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |

### `Search-PWSHCertutilCerts`

| Context | Test | Tag |
|---|---|---|
| No filters | restrict = GeneralFlags=0 | Unit |
| -Type Issued | restrict contains Disposition=20 | Unit |
| -Type Revoked | restrict contains Disposition=21 | Unit |
| Single -Requester | restrict contains RequesterName= | Unit |
| Multiple -Requester | Values joined with pipe (OR) | Unit |
| Multiple filter types | restrict contains all parts joined with comma | Unit |
| -NotBefore / -NotAfter | Correct MM/dd/yyyy format in restrict | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |

### `Show-PWSHCertutilCerts`

| Context | Test | Tag |
|---|---|---|
| Pipeline input | Extracts Profile/CAServer/RequestID from object | Unit |
| Direct parameters | Uses explicit parameters | Unit |
| RequestID not found | Write-Error, no output | Unit |
| Valid certificate bytes | Returns decoded ASN.1 object | Unit |
| -Profile omitted (Direct set) | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real cert decode | Subject/Issuer populated correctly | Integration |

### `Get-PWSHCertutilCertStatus`

| Context | Test | Tag |
|---|---|---|
| Pipeline input | Extracts metadata from piped object | Unit |
| Disposition=20 | Status = 'Issued' | Unit |
| Disposition=21 | Status = 'Revoked', CRLInfo populated | Unit |
| Unknown disposition | Status contains raw value | Unit |
| -Profile omitted (Direct set) | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Disposition=21 | CRLInfo.RevokedWhen returned as DateTime, not string | Unit |

### `Revoke-PWSHCertutilIssuedCerts`

| Context | Test | Tag |
|---|---|---|
| Named reason | Passes correct integer to certutil | Unit |
| Integer reason | Passed through directly | Unit |
| Invalid reason | Parameter validation rejects it | Unit |
| -WhatIf | Does not call Invoke-CertutilRevoke | Unit |
| Pipeline input | Extracts Profile/CAServer/SerialNumber | Unit |
| certutil returns FAILED | Write-Error emitted | Unit |
| -Profile omitted (Direct set) | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| -Profile tab completion (Direct set) | TabExpansion2 suggests configured profile names | Unit |
| -Profile invalid value (Direct set) | Rejected by ValidateSet before cmdlet body runs | Unit |
| Real revocation | Certificate status changes to Revoked | Integration |

### `Publish-PWSHCertutilCACrl`

| Context | Test | Tag |
|---|---|---|
| All CAs in profile | Invoke-CertutilCrl called once per CA | Unit |
| -CAFqdn filter | Called once only | Unit |
| -WhatIf | Does not call Invoke-CertutilCrl | Unit |
| CRL decode | CRLDecoded property populated | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real publish | LastWriteTime is recent | Integration |

### `Sync-PWSHCertutilCASchema`

| Context | Test | Tag |
|---|---|---|
| Profile with 2 CAs | Returns one result object per CA | Unit |
| -CAFqdn filter | Queries only the specified CA | Unit |
| CAFqdn not in profile | Throws | Unit |
| One CA fails | Writes error, does not throw | Unit |
| Profile on results | Every returned object has correct Profile | Unit |
| AvailableFields | Populated from ConvertFrom-CertutilSchema output | Unit |
| ValidatedOut | Excludes fields absent from schema | Unit |
| RemovedFields | Lists fields in config but not in schema | Unit |
| Intersection — 2 CAs | Field only on CA01 dropped from ValidatedOut | Unit |
| Identical schemas | SchemaConflicts is empty | Unit |
| Single CA queried | SchemaConflicts is empty (nothing to compare) | Unit |
| Divergent schemas | SchemaConflicts maps field to CAs that have it | Unit |
| Divergent schemas | Both result objects carry the same SchemaConflicts map | Unit |
| Divergent schemas | One warning emitted per conflicting field | Unit |
| Warning content | Message names the field and both CA sets | Unit |
| ConfigUpdated without -UpdateConfig | $false | Unit |
| -UpdateConfig | ConfigUpdated = $true, Set-Content called | Unit |
| -WhatIf | Set-Content not called | Unit |
| Written JSON content | Invalid field removed, valid field preserved | Unit |
| syncState updated | lastSync and fieldNameMap written when -UpdateConfig + probe succeeds | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real schema discovery | Returns real column names from CA | Integration |
| Real mismatch | Warning emitted when CA versions differ | Integration |

### `Submit-PWSHCertreqCSR`

| Context | Test | Tag |
|---|---|---|
| Issued immediately | Calls Invoke-CertreqSubmit with correct CertificateTemplate | Unit |
| Issued immediately | Returns object with Profile, CAServer, RequestID | Unit |
| Issued immediately | Certificate property populated via ConvertFrom-CertutilAsn1 | Unit |
| Status=Pending | ConvertFrom-CertutilAsn1 not called; Certificate is null | Unit |
| Status=Pending | RequestID and Status=Pending returned on output object | Unit |
| CA not in profile | Throws | Unit |
| Invoke-CertreqSubmit throws | Write-Error emitted | Unit |
| -Profile omitted | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real submission (auto-issue) | Certificate returned, Status=Issued | Integration |
| Real submission (manual) | Status=Pending, RequestID populated | Integration |

### `Get-PWSHCertreqCert`

| Context | Test | Tag |
|---|---|---|
| Status=Issued | Calls Invoke-CertreqRetrieve with correct RequestID | Unit |
| Status=Issued | Returns Profile, CAServer, RequestID | Unit |
| Status=Issued | Certificate property populated | Unit |
| Pipeline input | Extracts Profile/CAServer/RequestID from piped object | Unit |
| Status=Pending | ConvertFrom-CertutilAsn1 not called; Certificate is null | Unit |
| Invoke-CertreqRetrieve throws | Write-Error emitted | Unit |
| -Profile omitted (Direct set) | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real retrieve after approval | Certificate returned with correct Subject | Integration |

### `Approve-PWSHCertutilPendingCert`

| Context | Test | Tag |
|---|---|---|
| Direct parameters | Calls Invoke-CertutilResubmit with correct RequestID | Unit |
| -WhatIf | Does not call Invoke-CertutilResubmit | Unit |
| Pipeline input | Extracts Profile/CAServer/RequestID from piped object | Unit |
| Success | Returns object with Success=$true | Unit |
| Invoke-CertutilResubmit throws | Write-Error emitted | Unit |
| -Profile omitted (Direct set) | Falls back to the default profile | Unit |
| -Profile omitted, no default configured | Throws | Unit |
| Real approval | Pending request transitions to Issued on CA | Integration |

### Cmdlet aliases (`Tests\Public\Aliases.Tests.ps1`)

Singular-noun aliases registered in `Posh-Certutil.psm1` for the six cmdlets whose noun predates
the singular-noun guideline.

| Context | Test | Tag |
|---|---|---|
| `Get-PWSHCertutilIssuedCert` | Resolves to `Get-PWSHCertutilIssuedCerts` | Unit |
| `Get-PWSHCertutilRevokedCert` | Resolves to `Get-PWSHCertutilRevokedCerts` | Unit |
| `Get-PWSHCertutilShortTermExpiringCert` | Resolves to `Get-PWSHCertutilShortTermExpiringCerts` | Unit |
| `Revoke-PWSHCertutilIssuedCert` | Resolves to `Revoke-PWSHCertutilIssuedCerts` | Unit |
| `Search-PWSHCertutilCert` | Resolves to `Search-PWSHCertutilCerts` | Unit |
| `Show-PWSHCertutilCert` | Resolves to `Show-PWSHCertutilCerts` | Unit |
| Exported alias set | Matches the expected six names exactly (no more, no fewer) | Unit |

---

## Coverage matrix — Private functions

### Config layer (`Tests\Private\Config.Tests.ps1`)

Tested via `InModuleScope 'Posh-Certutil'`.

| Function | Scenario | Tag |
|---|---|---|
| `Read-ConfigFile` | File exists — returns PSCustomObject | Unit |
| `Read-ConfigFile` | File missing — returns empty profiles object | Unit |
| `Resolve-ProfileName` | ProfileName supplied — returned unchanged | Unit |
| `Resolve-ProfileName` | ProfileName omitted — returns the profile with defaultProfile=true | Unit |
| `Resolve-ProfileName` | ProfileName omitted, no profile marked default — throws | Unit |
| `New-ProfileDynamicParameter` | Returns a RuntimeDefinedParameterDictionary with a Profile parameter | Unit |
| `New-ProfileDynamicParameter` | ValidateSet populated with current profile names | Unit |
| `New-ProfileDynamicParameter` | ValidateSet omitted when no profiles exist | Unit |
| `New-ProfileDynamicParameter` | Mandatory defaults to $false; honors -Mandatory $true | Unit |
| `New-ProfileDynamicParameter` | ParameterSetName applied when specified | Unit |
| `Get-ProfileConfig` | Valid profile — returns profile object | Unit |
| `Get-ProfileConfig` | Invalid profile — throws with available list | Unit |
| `Get-CertutilViewParams` | issuedCerts operation — returns restrict + out | Unit |
| `Get-CertutilViewParams` | Substitution applied — {EXPIRE_DATE} replaced | Unit |
| `Get-CertutilViewParams` | Missing restrict key — throws | Unit |
| `Invoke-ProfileAutoSync` | Already synced — returns profileConfig unchanged | Unit |
| `Invoke-ProfileAutoSync` | Not synced — emits warning, calls Get-CertutilFieldNameMap | Unit |
| `Invoke-ProfileAutoSync` | Probe fails — emits warning, returns profileConfig unchanged | Unit |
| `ConvertTo-ProfileSyncStateDateTime` | ISO 8601 lastSync string — parsed to DateTime | Unit |
| `ConvertTo-ProfileSyncStateDateTime` | syncState absent — returns object unchanged, no error | Unit |
| `ConvertTo-ProfileSyncStateDateTime` | syncState.lastSync null — no error | Unit |

### Session layer (`Tests\Private\Session.Tests.ps1`)

| Function | Scenario | Tag |
|---|---|---|
| `Test-CASession` | State not Opened — returns $false | Unit |
| `Test-CASession` | Invoke-Command fails — returns $false | Unit |
| `Test-CASession` | Healthy session — returns $true | Unit |
| `Get-CASession` | Pool hit alive — returns existing session | Unit |
| `Get-CASession` | Pool hit dead — evicts, creates new | Unit |
| `Get-CASession` | Pool miss — creates new session | Unit |
| `Get-CASession` | maxSessions exceeded — waits then creates | Unit |
| `Get-CASession` | Timeout — throws | Unit |
| `Remove-CASession` | Existing key — removes + closes | Unit |
| `Remove-CASession` | Missing key — no error | Unit |

### Certutil layer (`Tests\Private\Certutil.Tests.ps1`)

| Function | Scenario | Tag |
|---|---|---|
| `ConvertFrom-CertutilCsv` | Only header, no data — returns empty | Unit |
| `ConvertFrom-CertutilCsv` | Header + 2 data rows + certutil footer — returns 2 objects | Unit |
| `ConvertFrom-CertutilCsv` | Empty input — returns empty | Unit |
| `ConvertFrom-CertutilCsv` | FieldMap provided — renames localized headers to canonical names | Unit |
| `ConvertFrom-CertutilCsv` | Unmapped columns passed through unchanged | Unit |
| `ConvertFrom-CertutilCsv` | -CACulture not supplied — date-shaped columns stay strings (unchanged) | Unit |
| `ConvertFrom-CertutilCsv` | -CACulture supplied — NotBefore/NotAfter/RevokedEffectiveWhen parsed to DateTime | Unit |
| `ConvertFrom-CertutilCsv` | Non-US CACulture (fr-FR, day-first) — parses day/month correctly, not swapped | Unit |
| `ConvertFrom-CertutilCsv` | Empty date value — becomes $null, not an exception | Unit |
| `ConvertFrom-CertutilCsv` | Date parsing applied after FieldMap rename (operates on canonical names) | Unit |
| `ConvertFrom-CertutilCsv` | Unparseable date string — Write-Warning emitted, original string preserved | Unit |
| `Get-CertutilFieldNameMap` | Success — returns localized→canonical hashtable | Unit |
| `Get-CertutilFieldNameMap` | CA returns no CSV header — throws | Unit |
| `Get-CertutilFieldNameMap` | Column count mismatch — throws | Unit |
| `Get-CACulture` | Returns the culture name from the CA session | Unit |
| `Get-CACulture` | Invokes the remote command against the supplied session | Unit |
| `Get-CALocalDate` | Returns Today and ExpireDate from CA | Unit |
| `Get-CALocalDate` | Passes Days argument to remote scriptblock | Unit |
| `Invoke-CertutilView` | Certutil succeeds — returns stdout lines | Unit |
| `Invoke-CertutilView` | FAILED in stdout — throws with message | Unit |
| `Invoke-CertutilSchema` | Certutil succeeds — returns stdout lines | Unit |
| `Invoke-CertutilSchema` | FAILED in stdout — throws with message | Unit |
| `ConvertFrom-CertutilSchema` | Standard certutil -schema output — extracts 11 column names | Unit |
| `ConvertFrom-CertutilSchema` | Headers/separators/status lines excluded | Unit |
| `ConvertFrom-CertutilSchema` | Empty input — returns empty | Unit |
| `ConvertFrom-CertutilSchema` | Only status lines — returns empty | Unit |
| `Invoke-CertutilRevoke` | Named reason — passes correct code | Unit |
| `Invoke-CertutilRevoke` | FAILED in output — throws | Unit |
| `Invoke-CertutilResubmit` | Passes RequestID to certutil | Unit |
| `Invoke-CertutilResubmit` | Returns output on success | Unit |
| `Invoke-CertutilResubmit` | FAILED in output — throws | Unit |
| `Invoke-CertreqSubmit` | exitCode=0 + cert file — Status=Issued, CertBase64 populated | Unit |
| `Invoke-CertreqSubmit` | exitCode=0 + no cert file — Status=Pending | Unit |
| `Invoke-CertreqSubmit` | exitCode!=0 (Failed) — throws with message | Unit |
| `Invoke-CertreqRetrieve` | exitCode=0 + cert file — Status=Issued, CertBase64 populated | Unit |
| `Invoke-CertreqRetrieve` | exitCode=0 + no cert file — Status=Pending | Unit |
| `Invoke-CertreqRetrieve` | exitCode!=0 (Failed) — throws with message | Unit |
| `ConvertFrom-CertutilAsn1` | Valid base64 DER — returns decoded object | Unit |
| `ConvertFrom-CertutilAsn1` | Invalid base64 — throws | Unit |
| `Add-ResultMetadata` | Stamps Profile + CAServer on each piped object | Unit |

---

## Running the full suite

```powershell
Import-Module Pester -MinimumVersion 5.3
Invoke-Pester -Path .\Tests -Tag Unit -Output Detailed
```

Expected: all unit tests pass without a CA. Integration tests are skipped unless the `-Tag Integration` filter is included and a CA is reachable.
