# SnapCert
Automated Active Directory CA certificate renewal for domain-joined Windows machines.

## Requirements

- PowerShell 5.1+
- Domain-joined Windows machine with AD CS enrollment rights
- `certreq.exe` (included with Windows)
- Pester 5.x (testing only — not deployed to endpoints):
  ```powershell
  Install-Module -Name Pester -Force -SkipPublisherCheck
  ```

## Usage

```powershell
# Report certificates expiring within the configured threshold
.\src\SnapCert.ps1 -Scan

# Scan and renew expiring certificates
.\src\SnapCert.ps1 -Renew

# Simulate renewal without submitting to the CA
.\src\SnapCert.ps1 -Renew -DryRun

# Override the expiry threshold for this run
.\src\SnapCert.ps1 -Renew -DaysThreshold 14

# Register SnapCert as a daily Windows Scheduled Task (run as admin)
.\src\SnapCert.ps1 -Schedule

# Remove the scheduled task
.\src\SnapCert.ps1 -Unschedule
```

## Configuration

Copy `config\snapcert.default.json` to `C:\ProgramData\SnapCert\snapcert.json` and edit as needed. User config values override defaults; missing keys fall back to defaults automatically.

| Key | Default | Description |
|-----|---------|-------------|
| `DaysBeforeExpiry` | `30` | Renew certificates expiring within this many days |
| `CertificateTemplates` | `["Computer"]` | AD CS template names to scan (single template for renewal) |
| `CertStorePath` | `Cert:\LocalMachine\My` | Certificate store to scan |
| `LogFilePath` | `C:\ProgramData\SnapCert\snapcert.log` | Log file path |
| `LogRetentionDays` | `90` | Log entries older than this are trimmed |
| `LogToEventLog` | `true` | Also write to Windows Application Event Log |
| `EventLogSource` | `SnapCert` | Event Log source name |
| `ScheduleTaskName` | `SnapCert-AutoRenew` | Scheduled task name |
| `ScheduleRunTime` | `02:00` | Daily run time for the scheduled task |

## Project Structure

```
SnapCert/
├── src/
│   ├── SnapCert.ps1                # CLI entry point
│   └── modules/
│       ├── Logging.psm1            # File + Event Log logging with rotation
│       ├── Configuration.psm1      # JSON config load/save with defaults merging
│       ├── CertScanner.psm1        # Cert store scanning, expiry filtering
│       ├── CertRenewal.psm1        # certreq INF generation and renewal orchestration
│       └── Scheduler.psm1          # Windows Scheduled Task management
├── config/
│   └── snapcert.default.json       # Default configuration template
├── tests/
│   ├── TestHelpers.ps1             # Shared Pester mock helpers
│   ├── Smoke.Tests.ps1             # Pester installation smoke test
│   ├── Logging.Tests.ps1
│   ├── Configuration.Tests.ps1
│   ├── CertScanner.Tests.ps1
│   ├── CertRenewal.Tests.ps1
│   ├── Scheduler.Tests.ps1
│   └── SnapCert.Tests.ps1
└── docs/
    └── superpowers/
        └── plans/
            └── 2026-03-20-snapcert-core.md
```

## Running Tests

```powershell
# Full test suite
Invoke-Pester tests/ -Output Normal

# Single module
Invoke-Pester tests/CertScanner.Tests.ps1 -Output Normal
```

## Deployment

Deploy via SCCM as a script package. The scheduled task runs as `SYSTEM` and submits certificate renewal requests directly to the AD CS issuing CA via `certreq`. No proxy or CEP endpoint required.

## Compliance Notes

- Targets CIS Controls alignment
- Logs to Windows Application Event Log for SIEM consumption
- Log retention: 90 days, self-trimmed by the tool
- Pester is test-only and not deployed to endpoints (pending vendor approval for production pipeline use)
- Code signing deferred pending internal cert provisioning
