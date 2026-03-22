# SnapCert Admin Guide

## What SnapCert Does

SnapCert monitors the local Windows certificate store for AD CS-issued Computer certificates nearing expiry and automatically submits new enrollment requests to the AD CS issuing CA using `certreq.exe`. It is designed for domain-joined Windows Servers managed via SCCM where Group Policy autoenrollment is not in use. It runs as SYSTEM on a daily schedule and requires no user interaction after deployment.

---

## Requirements

- **OS:** Windows Server 2012 R2 or later
- **PowerShell:** 5.1 or later (included in all supported OS versions)
- **AD CS:** Machine must have Computer autoenrollment rights; online issuing CA reachable directly (no proxy, no CEP required)
- **Run-as account:** SYSTEM
- **`certreq.exe`:** Included with Windows Server by default — no installation required
- **No additional software** required on managed endpoints

---

## How It Works

1. Read `snapcert.json`, merging user values over defaults
2. Scan `Cert:\LocalMachine\My` for certificates matching the configured template and expiring within the threshold
3. For each expiring certificate, generate a PKCS10 INF request file with auto-detected Subject and SANs
4. Call `certreq -new` to generate a CSR from the INF
5. Call `certreq -submit` to submit the CSR to the AD CS issuing CA
6. Call `certreq -accept` to install the returned certificate into the machine store
7. Log each stage to file and (optionally) Windows Event Log
8. Clean up temp files (INF, REQ, CER) on success

---

## Certificate Request Details

- **Template:** `CertificateTemplates[0]` in config; default `Computer`
- **Key length:** 2048-bit RSA; not configurable via config
- **Exportable:** FALSE
- **Request type:** PKCS10
- **Subject:** `CN=<FQDN>` — auto-populated via DNS at request time
- **SANs (all auto-detected):**
  - `dns=<ShortName>` — from `$env:COMPUTERNAME`
  - `dns=<FQDN>` — from DNS reverse lookup
  - `ipaddress=<IP>` — first non-loopback IPv4 address
- **SAN detection failure:**
  - DNS failure (exception from `GetHostEntry` or `GetHostAddresses`): propagates as an unhandled terminating error. The last log entry before the crash is `"Enrolling new certificate for: CN=<subject> (expires <date>)"` at INFO level. Nothing is logged after that.
  - No IPv4 address found: `ipaddress=` is written with an empty value, request proceeds silently with an incomplete SAN.
  - Admins should verify SANs after the first renewal on any new machine type.

---

## Configuration Reference

User config at `C:\ProgramData\SnapCert\snapcert.json`. Missing keys fall back to defaults automatically. All values are used without pre-validation — an invalid value causes an unhandled terminating error at the point of use.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `DaysBeforeExpiry` | Integer | `30` | Renew certs expiring within this many days |
| `CertificateTemplates` | Array of strings | `["Computer"]` | AD CS template names. Must be exactly one entry for `-Renew` — throws a terminating error if more than one is configured. Multiple entries are supported for `-Scan` only (scans each template in sequence). Plural name anticipates future multi-template renewal. |
| `CertStorePath` | String | `Cert:\LocalMachine\My` | Certificate store to scan |
| `LogFilePath` | String | `C:\ProgramData\SnapCert\snapcert.log` | Log file path. Parent directory is created automatically if it does not exist. |
| `LogRetentionDays` | Integer | `90` | Age threshold for log trimming. **Rotation is not currently called automatically** — see Known Limitations. |
| `LogToEventLog` | Boolean | `true` | Mirror log entries to Windows Application Event Log. If `false`, no Event Log writes occur and the source is never registered. |
| `EventLogSource` | String | `SnapCert` | Event Log source name. Auto-registered on first write when `LogToEventLog` is `true`. |
| `ScheduleTaskName` | String | `SnapCert-AutoRenew` | Name of the Windows Scheduled Task |
| `ScheduleRunTime` | String | `02:00` | Daily run time (24-hour HH:mm format) |

---

## CLI Usage

All examples assume the script is at `C:\Program Files\SnapCert\src\SnapCert.ps1`. No `-WhatIf` support — use `-DryRun` to simulate.

| Switch | Purpose | Requires Elevation |
|--------|---------|-------------------|
| `-Scan` | Report expiring certs without renewing | No |
| `-Renew` | Scan and submit renewal requests to the CA | No (SYSTEM when scheduled) |
| `-DryRun` | Used with `-Renew`: simulates the full renewal loop without calling certreq. Scans for expiring certs, logs "Enrolling..." and "Enrollment succeeded..." for each, but skips all certreq calls. No INF/REQ/CER files are created. | No |
| `-DaysThreshold <n>` | Override the expiry threshold for this run only | No |
| `-Schedule` | Registers the daily scheduled task. Task name and run time come from config (`ScheduleTaskName`, `ScheduleRunTime`). Task runs as SYSTEM. If a task with the same name already exists, it is silently overwritten. Requires admin rights to write to Task Scheduler. | Yes |
| `-Unschedule` | Removes the scheduled task. No error if task does not exist. | Yes |
| `-ConfigPath <path>` | Use an alternate config file instead of `C:\ProgramData\SnapCert\snapcert.json` | No |

**Multi-template workaround:** Create a separate config file per template and use `-ConfigPath`. Recommended naming: `snapcert-Computer.json`, `snapcert-WebServer.json`. Example:

```powershell
.\SnapCert.ps1 -Renew -ConfigPath "C:\ProgramData\SnapCert\snapcert-WebServer.json"
```

---

## Logging and Monitoring

- **Log file:** `C:\ProgramData\SnapCert\snapcert.log`
- **Format:** `yyyy-MM-dd HH:mm:ss [LEVEL] Message` — one entry per line
- **Rotation:** `Invoke-SnapCertLogRotation` is implemented but **not called automatically during normal operation**. Log entries will accumulate indefinitely until rotation is wired up in a future release. Admins should monitor log file size or invoke rotation manually via a separate scheduled task. Estimated growth: ~200-500 bytes/day under normal operation (2-4 entries per run).
- **Event Log:** Windows Application log, source `SnapCert`, **Event ID 1000 for all entries**. Severity is in the `EntryType` field only — not in separate Event IDs.
  - `Information` — all normal operation messages
  - `Warning` — not currently produced (reserved for future use)
  - `Error` — renewal failure (e.g., certreq non-zero exit)
- **If Event Log write fails** (e.g., restricted ACL on a hardened host): the failure is non-fatal. A warning is printed to the console and execution continues. The file log entry is always written first.
- **Source registration:** Auto-registered on first write when `LogToEventLog=true`. No manual step required. If `LogToEventLog=false`, the source is never registered.
- **SIEM guidance:**
  - Alert on: `Source=SnapCert, EntryType=Error`
  - Heartbeat check: every run logs at least one `Information` entry with the message `Scanning for certificates expiring within <n> days.` (where `<n>` is the configured or overridden threshold). Absence of any `Source=SnapCert` entries for more than 25 hours (24h daily cadence + 1h buffer) indicates the scheduled task is not running.

---

## SCCM Deployment Notes

*Scripts are not yet written. This section documents planning intent.*

- **Install path:** `C:\Program Files\SnapCert\`
- **Runtime data / config path:** `C:\ProgramData\SnapCert\`
- **Detection method:** Registry key `HKLM:\SOFTWARE\SnapCert\Version`
- **Scheduled task:** `SnapCert-AutoRenew`, daily at 02:00, runs as SYSTEM
- **Execution policy:** `-ExecutionPolicy Bypass` at runtime; no machine-level policy change required
- **Upgrade (interim, manual):** Stop or disable the scheduled task before copying files to avoid a mid-copy execution. Copy new files over the existing install directory. Re-enable the task.
- **Uninstall (interim, manual):** Run `SnapCert.ps1 -Unschedule`, then delete `C:\Program Files\SnapCert\`. `C:\ProgramData\SnapCert\` (logs and config) is left intact for audit. Remove manually if desired.
- **Formal upgrade/uninstall procedures:** Not yet defined. Will be documented when SCCM scripts are written.

---

## Known Limitations

1. **Single template per `-Renew` run.** Configuring more than one entry in `CertificateTemplates` causes `-Renew` to throw a terminating error. Workaround: create a separate `snapcert.json` per template (e.g., `snapcert-WebServer.json`) and use `-ConfigPath` with a separate scheduled task per template.
2. **The original certificate is not removed after renewal.** After a successful renewal, the expiring certificate remains in the machine's certificate store. It is not automatically cleaned up. Admins may see duplicate certificates and should remove expired ones periodically. Renewal by thumbprint (`certreq -renew`) is planned for a future release.
3. **Log rotation is not automatic.** `Invoke-SnapCertLogRotation` is implemented but not called during normal operation. Log files will grow until this is addressed in a future release. Monitor log file size manually in the interim.
4. **No email alerting.** Renewal failures are written to the log and Event Log but no notification is sent. Email alerting via internal SMTP relay is planned for v1.1.
5. **Pester is a development dependency only.** The automated test suite uses Pester, which is never installed on managed machines and is pending vendor approval for use in CI/CD pipelines.
