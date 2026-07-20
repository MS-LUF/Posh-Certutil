# Configuration Schema — Posh-Certutil.json

## File location

`<ModuleRoot>\Config\Posh-Certutil.json`

The path is set in `Posh-Certutil.psm1` as `$script:ConfigPath` and is read on every cmdlet call (no cache). Editing the file takes effect immediately on the next call without reloading the module.

---

## Top-level structure

```json
{
  "version": "1.0",
  "profiles": {
    "<profile-name>": { ... }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `version` | string | Schema version. Currently `"1.0"`. |
| `profiles` | object | Named profile objects. Add, remove, or rename freely. |

---

## Profile object

```json
{
  "description": "Human-readable label",
  "defaultProfile": false,
  "remoting": { ... },
  "cas": [ ... ],
  "certutilView": { ... }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `defaultProfile` | bool | `false` | When `true`, this profile is used by every cmdlet's `-Profile` parameter when it is omitted. Only one profile should be `true` at a time — `Set-PWSHCertutilConfig -DefaultProfile $true` enforces this by clearing the flag on every other profile. If no profile has `defaultProfile: true`, cmdlets throw when called without `-Profile`. |

### `remoting`

```json
{
  "useTls": true,
  "port": 5986,
  "maxSessionsPerCA": 2
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `useTls` | bool | `true` | `true` → HTTPS/5986 (`-UseSSL`). `false` → HTTP/5985. |
| `port` | int | 5986 or 5985 | WinRM port. `Set-PWSHCertutilConfig` defaults this from `useTls`. |
| `maxSessionsPerCA` | int | `2` | Maximum concurrent pooled WinRM sessions per CA. `Get-CASession` blocks up to 30 s waiting for a slot. |

### `cas` array

```json
[
  { "fqdn": "ca01.corp.local", "displayName": "Issuing CA 01" },
  { "fqdn": "ca02.corp.local", "displayName": "Issuing CA 02" }
]
```

| Field | Type | Description |
|---|---|---|
| `fqdn` | string | Fully-qualified domain name used as the WinRM `ComputerName`. |
| `displayName` | string | Human label. Not used programmatically. |

### `certutilView`

Controls what certutil `-restrict` and `-out` strings are sent for each operation.

```json
{
  "restrict": {
    "issuedCerts":   "<certutil restrict expression>",
    "revokedCerts":  "<certutil restrict expression>",
    "expiringCerts": "<certutil restrict expression with {EXPIRE_DATE}>",
    "search":        "{DYNAMIC}"
  },
  "out": {
    "issuedCerts":   ["Field1", "Field2"],
    "revokedCerts":  ["Field1", "Field2"],
    "expiringCerts": ["Field1", "Field2"],
    "search":        ["Field1", "Field2"]
  }
}
```

#### `restrict` rules

- Standard certutil restrict syntax: `Field=Value,Field2>Value2`.
- Multiple conditions joined with `,` are AND. Multiple values for one field joined with `|` are OR.
- `{EXPIRE_DATE}` is a substitution token replaced at runtime with `MM/dd/yyyy` of `(Get-Date).AddDays($Days)`.
- `{DYNAMIC}` in `search.restrict` is a marker only — `Search-PWSHCertutilCerts` ignores this field and builds the restrict string from its own parameters at call time.

#### `out` rules

- An ordered array of certutil field names. Joined to a comma-separated string before calling certutil.
- **These names must match the CA database schema.** Common names: `RequestID`, `RequesterName`, `CommonName`, `NotBefore`, `NotAfter`, `SerialNumber`, `CertificateTemplate`, `Disposition`, `RevokedReason`, `RevokedEffectiveWhen`, `BinaryCertificate`.
- Field names are case-sensitive and CA-version-dependent. Validate against your CAs using `certutil -schema` on the CA.
- Adding or removing fields here changes what properties appear on output objects immediately — no module reload required.

### `syncState`

Populated automatically by `Sync-PWSHCertutilCASchema -UpdateConfig` or by the first query on the profile (auto-sync). **Do not edit manually.**

```json
{
  "syncState": {
    "lastSync": "2026-06-30T10:15:00.0000000Z",
    "fieldNameMap": {
      "Issued Request ID": "RequestID",
      "Requester Name":    "RequesterName",
      "Issued Common Name": "CommonName"
    }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `lastSync` | ISO 8601 string on disk | Timestamp of the last successful sync, written as an invariant-culture `[datetime]::UtcNow.ToString('o')` string. If absent or `null`, auto-sync triggers on the next query. `Get-PWSHCertutilConfig` returns it as a real `[datetime]` (via `ConvertTo-ProfileSyncStateDateTime`) — the string form only exists in the JSON file itself. |
| `fieldNameMap` | object | Maps each localized CSV column header (as returned by certutil) to its canonical internal field name. Used by `ConvertFrom-CertutilCsv` to rename columns so pipeline-chaining between cmdlets works regardless of the CA server locale. |

**Why this exists:** `certutil -view csv` outputs localized column headers (e.g. `"Issued Request ID"` on English, different strings on French, German, etc.). Without the map the output objects have locale-specific property names, which breaks cmdlets that read `$InputObject.RequestID`.

**Auto-sync behaviour:** When a query cmdlet runs and `syncState.lastSync` is absent or `null`, the module automatically opens a session to the first CA in the profile, runs a probe query (`certutil -view -restrict RequestID=0 csv`) to discover the localized headers, builds the map, and saves it to the JSON. A `Write-Warning` is emitted to make the side-effect visible. The first query takes slightly longer; all subsequent queries use the cached map.

**Date-typed output columns:** The same localized-header problem applies to certutil's date/time columns (`NotBefore`, `NotAfter`, `RevokedEffectiveWhen`) — certutil writes them in the **CA server's** locale, not the admin machine's. `ConvertFrom-CertutilCsv` parses these into real `[datetime]` values using a culture name fetched per-CA via the `Get-CACulture` private helper (`(Get-Culture).Name` run on the CA itself), never the admin machine's own culture. See [Docs/Architecture.md](Architecture.md#output-object-contract) for the full contract.

---

## Certutil disposition values (reference)

| Value | Meaning |
|---|---|
| `20` | Issued |
| `21` | Revoked |
| `30` | Pending |
| `31` | Failed |

Source: sysadmins.lv disposition values article (see README).

---

## Managing profiles with Set-PWSHCertutilConfig

`Set-PWSHCertutilConfig` writes a new profile with default restrict/out values. To customise restrict or out columns, edit the JSON directly after creating the profile. The next cmdlet call will pick up the changes.

```powershell
Set-PWSHCertutilConfig -Profile 'prod-pki' `
    -CAFqdn 'ca01.corp.local','ca02.corp.local' `
    -DisplayName 'Root CA','Issuing CA' `
    -UseTls $true -Description 'Production PKI'
```

### Default profile

Mark a profile as the default so every cmdlet's `-Profile` parameter can be omitted:

```powershell
Set-PWSHCertutilConfig -Profile 'prod-pki' -CAFqdn 'ca01.corp.local' -DefaultProfile $true
```

`Resolve-ProfileName` (private helper) resolves `-Profile` on every cmdlet call: if `-Profile` is bound it is used as-is; otherwise the profile with `defaultProfile: true` is used; if no such profile exists, the cmdlet throws.

### Tab completion and validation on -Profile

On every cmdlet except `Set-PWSHCertutilConfig`, `-Profile` is a dynamic parameter (see
[Docs/Architecture.md](Architecture.md#the-dynamic--profile-parameter)) with a `ValidateSet` built
from the current profile names in this JSON file. That means:

- Pressing Tab after `-Profile ` on any of those cmdlets suggests only the profiles currently defined here.
- Supplying a name that isn't in `profiles` fails PowerShell parameter binding immediately, before the cmdlet runs.
- The list is read fresh from disk on every call — add, rename, or remove a profile here and the next Tab-completion/validation reflects it with no module reload.

`Set-PWSHCertutilConfig` deliberately keeps `-Profile` unrestricted since its purpose is to create profiles that don't exist yet.
