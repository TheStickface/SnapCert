# SnapCert
Automated Active Directory CA certificate renewal for domain-joined machines.

## Requirements
- PowerShell 5.1+
- Pester 5.x (`Install-Module -Name Pester -Force -SkipPublisherCheck`)
- Domain-joined Windows machine with AD CS enrollment rights

## Project Structure
```
snapcert-core/
├── config/
│   └── snapcert.default.json   # Default runtime configuration
├── tests/
│   ├── TestHelpers.ps1         # Shared Pester test helpers
│   └── Smoke.Tests.ps1         # Smoke tests
└── docs/
```

## Running Tests
```powershell
Invoke-Pester tests/Smoke.Tests.ps1 -Output Normal
```

## Configuration
Edit `config/snapcert.default.json` to adjust renewal thresholds, certificate templates, log paths, and scheduler settings.
