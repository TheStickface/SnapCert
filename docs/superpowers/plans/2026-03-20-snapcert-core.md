# SnapCert Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PowerShell-based tool that detects expiring AD CS Computer certificates on domain-joined Windows machines and automatically renews them.

**Architecture:** A set of focused PowerShell modules (Scanner, Renewal, Config, Scheduler, Logging) wired together by a main CLI entry point (`SnapCert.ps1`). Configuration is stored in a JSON file. The tool runs on the local machine as the domain computer account, submitting renewal requests directly to the AD CS CA via `certreq`. Scheduling is implemented via Windows Task Scheduler.

**Tech Stack:** PowerShell 5.1+, Pester 5.x (testing), certreq (certificate requests), Windows Task Scheduler (scheduling), Windows Event Log + file-based logging.

---

## File Map

| File | Responsibility |
|------|---------------|
| `src/SnapCert.ps1` | CLI entry point, parameter parsing, module orchestration |
| `src/modules/CertScanner.psm1` | Query local cert store, filter by template and expiry threshold |
| `src/modules/CertRenewal.psm1` | Build and submit certreq renewal requests, install renewed certs |
| `src/modules/Configuration.psm1` | Read/write JSON config, validate and apply defaults |
| `src/modules/Scheduler.psm1` | Create/update/remove Windows Scheduled Tasks for SnapCert |
| `src/modules/Logging.psm1` | Write structured log entries to file and Windows Event Log |
| `config/snapcert.default.json` | Default configuration template (shipped with tool) |
| `tests/TestHelpers.ps1` | Shared mock factory helpers used across test files (not a test itself) |
| `tests/Smoke.Tests.ps1` | Pester installation smoke test |
| `tests/CertScanner.Tests.ps1` | Pester tests for cert scanning logic |
| `tests/CertRenewal.Tests.ps1` | Pester tests for renewal request building and certreq orchestration |
| `tests/Configuration.Tests.ps1` | Pester tests for config load/save/defaults |
| `tests/Scheduler.Tests.ps1` | Pester tests for scheduled task management |
| `tests/Logging.Tests.ps1` | Pester tests for log output |
| `tests/SnapCert.Tests.ps1` | Pester tests for CLI orchestration (module wiring, parameter routing) |

---

## Task 1: Tooling and Project Scaffold

**Files:**
- Create: `tests/TestHelpers.ps1`
- Create: `config/snapcert.default.json`
- Modify: `README.md`

- [ ] **Step 1.1: Install Pester**

Run in PowerShell (as admin):
```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```
Expected: Pester 5.x installed. Verify with:
```powershell
Get-Module -Name Pester -ListAvailable | Select-Object Name, Version
```

- [ ] **Step 1.2: Create test helper file**

Create `tests/TestHelpers.ps1`:
```powershell
# Shared helpers for SnapCert Pester tests

function New-MockCertificate {
    param(
        [int]$DaysUntilExpiry = 20,
        [string]$Subject = "CN=TESTMACHINE",
        [string]$Thumbprint = "AABBCCDD1122334455667788AABBCCDD11223344",
        [string]$TemplateName = "Computer"
    )

    $notAfter = (Get-Date).AddDays($DaysUntilExpiry)

    $mockExt = [PSCustomObject]@{
        Oid    = [PSCustomObject]@{ FriendlyName = "Certificate Template Name" }
        _value = $TemplateName
    }
    $mockExt | Add-Member -MemberType ScriptMethod -Name Format -Value { param($t) return $this._value } -Force

    return [PSCustomObject]@{
        Subject       = $Subject
        Thumbprint    = $Thumbprint
        NotAfter      = $notAfter
        HasPrivateKey = $true
        Extensions    = @($mockExt)
    }
}
```

- [ ] **Step 1.3: Create default config file**

Create `config/snapcert.default.json`:
```json
{
  "DaysBeforeExpiry": 30,
  "CertificateTemplates": ["Computer"],
  "CertStorePath": "Cert:\\LocalMachine\\My",
  "LogFilePath": "C:\\ProgramData\\SnapCert\\snapcert.log",
  "LogToEventLog": true,
  "EventLogSource": "SnapCert",
  "ScheduleTaskName": "SnapCert-AutoRenew",
  "ScheduleRunTime": "02:00"
}
```

- [ ] **Step 1.4: Write a smoke test to confirm Pester works**

Create `tests/Smoke.Tests.ps1`:
```powershell
Describe "Pester smoke test" {
    It "arithmetic works" {
        (1 + 1) | Should -Be 2
    }
}
```

- [ ] **Step 1.5: Run smoke test**

```powershell
cd C:\Dev\SnapCert
Invoke-Pester tests/Smoke.Tests.ps1 -Output Normal
```
Expected: `1 test passed`

- [ ] **Step 1.6: Commit**

```powershell
git add config/snapcert.default.json tests/TestHelpers.ps1 tests/Smoke.Tests.ps1 README.md
git commit -m "feat: project scaffold, Pester tooling, default config"
```

---

## Task 2: Logging Module

**Files:**
- Create: `src/modules/Logging.psm1`
- Create: `tests/Logging.Tests.ps1`

Build logging first — every other module depends on it.

- [ ] **Step 2.1: Write failing tests**

Create `tests/Logging.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Logging.psm1" -Force
}

Describe "Write-SnapCertLog" {
    BeforeEach {
        $script:testLogPath = "$env:TEMP\snapcert_test_$([System.Guid]::NewGuid().ToString('N')).log"
    }
    AfterEach {
        if (Test-Path $script:testLogPath) { Remove-Item $script:testLogPath -Force }
    }

    It "creates log file if it does not exist" {
        Write-SnapCertLog -Message "hello" -Level "INFO" -LogFilePath $script:testLogPath
        $script:testLogPath | Should -Exist
    }

    It "writes message to log file" {
        Write-SnapCertLog -Message "test message" -Level "INFO" -LogFilePath $script:testLogPath
        $content = Get-Content $script:testLogPath -Raw
        $content | Should -Match "test message"
    }

    It "includes log level in output" {
        Write-SnapCertLog -Message "something failed" -Level "ERROR" -LogFilePath $script:testLogPath
        $content = Get-Content $script:testLogPath -Raw
        $content | Should -Match "\[ERROR\]"
    }

    It "includes timestamp in output" {
        Write-SnapCertLog -Message "timed" -Level "INFO" -LogFilePath $script:testLogPath
        $content = Get-Content $script:testLogPath -Raw
        $content | Should -Match "\d{4}-\d{2}-\d{2}"
    }

    It "appends to existing log file" {
        Write-SnapCertLog -Message "first" -Level "INFO" -LogFilePath $script:testLogPath
        Write-SnapCertLog -Message "second" -Level "INFO" -LogFilePath $script:testLogPath
        $lines = Get-Content $script:testLogPath
        $lines.Count | Should -Be 2
    }
}
```

- [ ] **Step 2.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/Logging.Tests.ps1 -Output Normal
```
Expected: FAIL — module not found

- [ ] **Step 2.3: Implement Logging module**

Create `src/modules/Logging.psm1`:
```powershell
function Write-SnapCertLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO",

        [string]$LogFilePath = "C:\ProgramData\SnapCert\snapcert.log",

        [bool]$LogToEventLog = $false,

        [string]$EventLogSource = "SnapCert"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp [$Level] $Message"

    $logDir = Split-Path $LogFilePath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Add-Content -Path $LogFilePath -Value $entry

    if ($LogToEventLog) {
        $eventType = switch ($Level) {
            "ERROR"   { "Error" }
            "WARNING" { "Warning" }
            default   { "Information" }
        }
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
            New-EventLog -LogName Application -Source $EventLogSource -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName Application -Source $EventLogSource -EventId 1000 -EntryType $eventType -Message $Message
    }
}

Export-ModuleMember -Function Write-SnapCertLog
```

- [ ] **Step 2.4: Run tests to confirm they pass**

```powershell
Invoke-Pester tests/Logging.Tests.ps1 -Output Normal
```
Expected: `5 tests passed`

- [ ] **Step 2.5: Commit**

```powershell
git add src/modules/Logging.psm1 tests/Logging.Tests.ps1
git commit -m "feat: add Logging module with file and event log output"
```

---

## Task 3: Configuration Module

**Files:**
- Create: `src/modules/Configuration.psm1`
- Create: `tests/Configuration.Tests.ps1`

- [ ] **Step 3.1: Write failing tests**

Create `tests/Configuration.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Configuration.psm1" -Force
    $script:defaultConfigPath = "$PSScriptRoot/../config/snapcert.default.json"
}

Describe "Get-SnapCertConfig" {
    BeforeEach {
        $script:testConfigPath = "$env:TEMP\snapcert_config_$([System.Guid]::NewGuid().ToString('N')).json"
    }
    AfterEach {
        if (Test-Path $script:testConfigPath) { Remove-Item $script:testConfigPath -Force }
    }

    It "returns default config when no config file exists" {
        $config = Get-SnapCertConfig -ConfigPath $script:testConfigPath -DefaultConfigPath $script:defaultConfigPath
        $config.DaysBeforeExpiry | Should -Be 30
    }

    It "returns user config values when config file exists" {
        @{ DaysBeforeExpiry = 14; CertificateTemplates = @("Computer") } | ConvertTo-Json | Set-Content $script:testConfigPath
        $config = Get-SnapCertConfig -ConfigPath $script:testConfigPath -DefaultConfigPath $script:defaultConfigPath
        $config.DaysBeforeExpiry | Should -Be 14
    }

    It "fills missing keys with defaults" {
        @{ DaysBeforeExpiry = 7 } | ConvertTo-Json | Set-Content $script:testConfigPath
        $config = Get-SnapCertConfig -ConfigPath $script:testConfigPath -DefaultConfigPath $script:defaultConfigPath
        $config.LogToEventLog | Should -Be $true
    }
}

Describe "Save-SnapCertConfig" {
    BeforeEach {
        $script:testConfigPath = "$env:TEMP\snapcert_config_$([System.Guid]::NewGuid().ToString('N')).json"
    }
    AfterEach {
        if (Test-Path $script:testConfigPath) { Remove-Item $script:testConfigPath -Force }
    }

    It "writes config to JSON file" {
        $config = [PSCustomObject]@{ DaysBeforeExpiry = 21 }
        Save-SnapCertConfig -Config $config -ConfigPath $script:testConfigPath
        $script:testConfigPath | Should -Exist
    }

    It "persists config values correctly" {
        $config = [PSCustomObject]@{ DaysBeforeExpiry = 21 }
        Save-SnapCertConfig -Config $config -ConfigPath $script:testConfigPath
        $saved = Get-Content $script:testConfigPath | ConvertFrom-Json
        $saved.DaysBeforeExpiry | Should -Be 21
    }
}
```

- [ ] **Step 3.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/Configuration.Tests.ps1 -Output Normal
```
Expected: FAIL

- [ ] **Step 3.3: Implement Configuration module**

Create `src/modules/Configuration.psm1`:
```powershell
function Get-SnapCertConfig {
    param(
        [string]$ConfigPath = "C:\ProgramData\SnapCert\snapcert.json",
        [string]$DefaultConfigPath = "$PSScriptRoot\..\..\config\snapcert.default.json"
    )

    $defaults = Get-Content $DefaultConfigPath -Raw | ConvertFrom-Json

    if (-not (Test-Path $ConfigPath)) {
        return $defaults
    }

    $user = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    # Merge: user values override defaults, missing keys fall back to defaults
    $merged = $defaults.PSObject.Copy()
    foreach ($prop in $user.PSObject.Properties) {
        $merged.$($prop.Name) = $prop.Value
    }

    return $merged
}

function Save-SnapCertConfig {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$ConfigPath = "C:\ProgramData\SnapCert\snapcert.json"
    )

    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
}

Export-ModuleMember -Function Get-SnapCertConfig, Save-SnapCertConfig
```

- [ ] **Step 3.4: Run tests to confirm they pass**

```powershell
Invoke-Pester tests/Configuration.Tests.ps1 -Output Normal
```
Expected: `5 tests passed`

- [ ] **Step 3.5: Commit**

```powershell
git add src/modules/Configuration.psm1 tests/Configuration.Tests.ps1
git commit -m "feat: add Configuration module with defaults merging"
```

---

## Task 4: Certificate Scanner Module

**Files:**
- Create: `src/modules/CertScanner.psm1`
- Create: `tests/CertScanner.Tests.ps1`

- [ ] **Step 4.1: Write failing tests**

Create `tests/CertScanner.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    Import-Module "$PSScriptRoot/../src/modules/CertScanner.psm1" -Force
}

Describe "Get-ExpiringCertificates" {
    It "returns certificates expiring within threshold" {
        $mockCerts = @(
            New-MockCertificate -DaysUntilExpiry 20
        )
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 1
    }

    It "excludes certificates not yet near expiry" {
        $mockCerts = @(
            New-MockCertificate -DaysUntilExpiry 60
        )
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 0
    }

    It "excludes certificates without private key" {
        $cert = New-MockCertificate -DaysUntilExpiry 10
        $cert.HasPrivateKey = $false
        Mock Get-ChildItem { return @($cert) } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 0
    }

    It "returns DaysUntilExpiry property on results" {
        $mockCerts = @(New-MockCertificate -DaysUntilExpiry 15)
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result[0].DaysUntilExpiry | Should -BeLessOrEqual 15
    }

    It "returns empty array when no certificates match" {
        Mock Get-ChildItem { return @() } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 4.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/CertScanner.Tests.ps1 -Output Normal
```
Expected: FAIL

- [ ] **Step 4.3: Implement CertScanner module**

Create `src/modules/CertScanner.psm1`:
```powershell
function Get-ExpiringCertificates {
    param(
        [int]$DaysThreshold = 30,
        [string]$Template = "Computer",
        [string]$CertStorePath = "Cert:\LocalMachine\My"
    )

    $thresholdDate = (Get-Date).AddDays($DaysThreshold)

    $certs = Get-ChildItem -Path $CertStorePath |
        Where-Object { $_.HasPrivateKey -eq $true } |
        Where-Object { $_.NotAfter -lt $thresholdDate }

    if ($Template) {
        $certs = $certs | Where-Object {
            $_.Extensions | Where-Object {
                $_.Oid.FriendlyName -eq "Certificate Template Name" -and
                $_.Format($false) -eq $Template
            }
        }
    }

    return $certs | Select-Object Subject, Thumbprint, NotAfter,
        @{N = "DaysUntilExpiry"; E = { [math]::Floor(($_.NotAfter - (Get-Date)).TotalDays) } }
}

Export-ModuleMember -Function Get-ExpiringCertificates
```

- [ ] **Step 4.4: Run tests to confirm they pass**

```powershell
Invoke-Pester tests/CertScanner.Tests.ps1 -Output Normal
```
Expected: `5 tests passed`

- [ ] **Step 4.5: Commit**

```powershell
git add src/modules/CertScanner.psm1 tests/CertScanner.Tests.ps1
git commit -m "feat: add CertScanner module for expiry detection"
```

---

## Task 5a: Certificate INF Request Generation

**Files:**
- Create: `src/modules/CertRenewal.psm1` (partial — `New-CertRenewalRequest` only)
- Create: `tests/CertRenewal.Tests.ps1` (partial)

> **Design note:** `certreq` performs *new enrollment*, not a targeted renewal by thumbprint. A new key pair is generated and a fresh certificate is issued. The existing expiring certificate is left in the store until the CA or an admin removes it. Targeted renewal by thumbprint (`certreq -renew`) is deferred — see Deferred section.

- [ ] **Step 5a.1: Write failing tests for INF generation**

Create `tests/CertRenewal.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    Import-Module "$PSScriptRoot/../src/modules/CertRenewal.psm1" -Force
}

Describe "New-CertRenewalRequest" {
    It "creates an INF file at the specified path" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath
        $infPath | Should -Exist
        Remove-Item $infPath -Force
    }

    It "INF file contains the correct template name" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "WebServer" -InfPath $infPath
        $content = Get-Content $infPath -Raw
        $content | Should -Match "WebServer"
        Remove-Item $infPath -Force
    }

    It "INF file sets MachineKeySet to TRUE" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath
        $content = Get-Content $infPath -Raw
        $content | Should -Match "MachineKeySet = TRUE"
        Remove-Item $infPath -Force
    }
}
```

- [ ] **Step 5a.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/CertRenewal.Tests.ps1 -Output Normal
```
Expected: FAIL

- [ ] **Step 5a.3: Implement `New-CertRenewalRequest`**

Create `src/modules/CertRenewal.psm1` with only the INF generation function (orchestration added in Task 5b):
```powershell
function New-CertRenewalRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [string]$InfPath = "$env:TEMP\snapcert_renewal.inf",

        [int]$KeyLength = 2048
    )

    $inf = @"
[Version]
Signature = "`$Windows NT`$"

[NewRequest]
Subject = ""
MachineKeySet = TRUE
KeyLength = $KeyLength
KeySpec = 1
Exportable = FALSE
RequestType = PKCS10

[RequestAttributes]
CertificateTemplate = $Template
"@

    $inf | Out-File -FilePath $InfPath -Encoding ASCII
}

Export-ModuleMember -Function New-CertRenewalRequest
```

- [ ] **Step 5a.4: Run tests to confirm they pass**

```powershell
Invoke-Pester tests/CertRenewal.Tests.ps1 -Output Normal
```
Expected: `3 tests passed`

- [ ] **Step 5a.5: Commit**

```powershell
git add src/modules/CertRenewal.psm1 tests/CertRenewal.Tests.ps1
git commit -m "feat: add CertRenewal INF request generation"
```

---

## Task 5b: Certificate Renewal Orchestration

**Files:**
- Modify: `src/modules/CertRenewal.psm1` (add `Invoke-CertificateRenewal`)
- Modify: `tests/CertRenewal.Tests.ps1` (add orchestration tests)

> **Test design note:** `DryRun $true` short-circuits before reaching `Start-Process`, so it cannot be used to test certreq exit-code handling. The `Start-Process` mock tests use `DryRun $false` and also mock `New-CertRenewalRequest` to prevent actual file I/O and certreq calls.

- [ ] **Step 5b.1: Add failing orchestration tests**

Append to `tests/CertRenewal.Tests.ps1`:
```powershell
Describe "Invoke-CertificateRenewal" {
    It "returns success without calling certreq when DryRun is true" {
        # DryRun short-circuits — no Start-Process call. Verify the result shape only.
        $result = Invoke-CertificateRenewal -Template "Computer" -DryRun $true
        $result.Success | Should -Be $true
        $result.Message | Should -Match "DryRun"
    }

    It "returns success result when all certreq stages exit 0" {
        Mock New-CertRenewalRequest {} -ModuleName CertRenewal
        Mock Start-Process {
            return [PSCustomObject]@{ ExitCode = 0 }
        } -ModuleName CertRenewal

        $result = Invoke-CertificateRenewal -Template "Computer" -DryRun $false
        $result.Success | Should -Be $true
    }

    It "returns failure when certreq -new exits non-zero" {
        Mock New-CertRenewalRequest {} -ModuleName CertRenewal
        Mock Start-Process {
            return [PSCustomObject]@{ ExitCode = 1 }
        } -ModuleName CertRenewal

        $result = Invoke-CertificateRenewal -Template "Computer" -DryRun $false
        $result.Success | Should -Be $false
        $result.Message | Should -Match "certreq -new failed"
    }

    It "returns failure when certreq -submit exits non-zero" {
        Mock New-CertRenewalRequest {} -ModuleName CertRenewal
        $callCount = 0
        Mock Start-Process {
            $script:callCount++
            if ($script:callCount -eq 1) { return [PSCustomObject]@{ ExitCode = 0 } }
            return [PSCustomObject]@{ ExitCode = 1 }
        } -ModuleName CertRenewal

        $result = Invoke-CertificateRenewal -Template "Computer" -DryRun $false
        $result.Success | Should -Be $false
        $result.Message | Should -Match "certreq -submit failed"
    }
}
```

- [ ] **Step 5b.2: Run tests to confirm new tests fail**

```powershell
Invoke-Pester tests/CertRenewal.Tests.ps1 -Output Normal
```
Expected: 3 existing pass, 4 new fail

- [ ] **Step 5b.3: Add `Invoke-CertificateRenewal` to CertRenewal module**

Append to `src/modules/CertRenewal.psm1` (keep `New-CertRenewalRequest`, replace the `Export-ModuleMember` line, then add below):
```powershell
function Invoke-CertificateRenewal {
    param(
        [string]$Template = "Computer",
        [bool]$DryRun = $false,
        [string]$WorkDir = $env:TEMP
    )

    if ($DryRun) {
        return [PSCustomObject]@{ Success = $true; Message = "DryRun: skipped certreq execution" }
    }

    $infPath = Join-Path $WorkDir "snapcert_renewal.inf"
    $reqPath = Join-Path $WorkDir "snapcert_renewal.req"
    $cerPath = Join-Path $WorkDir "snapcert_renewal.cer"

    New-CertRenewalRequest -Template $Template -InfPath $infPath

    # Stage 1: Generate CSR
    $newResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-new -q `"$infPath`" `"$reqPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($newResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -new failed (exit $($newResult.ExitCode))" }
    }

    # Stage 2: Submit to CA
    $submitResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-submit -q `"$reqPath`" `"$cerPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($submitResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -submit failed (exit $($submitResult.ExitCode))" }
    }

    # Stage 3: Accept and install certificate
    $acceptResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-accept `"$cerPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($acceptResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -accept failed (exit $($acceptResult.ExitCode))" }
    }

    # Cleanup temp files
    @($infPath, $reqPath, $cerPath) | Where-Object { Test-Path $_ } | Remove-Item -Force

    return [PSCustomObject]@{ Success = $true; Message = "Certificate enrolled successfully" }
}

Export-ModuleMember -Function New-CertRenewalRequest, Invoke-CertificateRenewal
```

- [ ] **Step 5b.4: Run full CertRenewal test suite**

```powershell
Invoke-Pester tests/CertRenewal.Tests.ps1 -Output Normal
```
Expected: `7 tests passed`

- [ ] **Step 5b.5: Commit**

```powershell
git add src/modules/CertRenewal.psm1 tests/CertRenewal.Tests.ps1
git commit -m "feat: add certreq orchestration to CertRenewal module"
```

---

## Task 6: Scheduler Module

**Files:**
- Create: `src/modules/Scheduler.psm1`
- Create: `tests/Scheduler.Tests.ps1`

- [ ] **Step 6.1: Write failing tests**

Create `tests/Scheduler.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Scheduler.psm1" -Force
}

Describe "Register-SnapCertSchedule" {
    BeforeAll {
        Mock Register-ScheduledTask { return $null } -ModuleName Scheduler
        Mock New-ScheduledTaskAction { return [PSCustomObject]@{ Execute = "powershell.exe" } } -ModuleName Scheduler
        Mock New-ScheduledTaskTrigger { return [PSCustomObject]@{ Daily = $true } } -ModuleName Scheduler
        Mock New-ScheduledTaskPrincipal { return [PSCustomObject]@{ RunLevel = "Highest" } } -ModuleName Scheduler
        Mock New-ScheduledTaskSettingsSet { return [PSCustomObject]@{} } -ModuleName Scheduler
    }

    It "calls Register-ScheduledTask" {
        Register-SnapCertSchedule -ScriptPath "C:\Tools\SnapCert.ps1" -RunTime "02:00" -TaskName "SnapCert-Test"
        Should -Invoke Register-ScheduledTask -ModuleName Scheduler -Times 1
    }
}

Describe "Unregister-SnapCertSchedule" {
    It "calls Unregister-ScheduledTask with correct task name" {
        Mock Unregister-ScheduledTask { return $null } -ModuleName Scheduler
        Mock Get-ScheduledTask {
            return [PSCustomObject]@{ TaskName = "SnapCert-AutoRenew" }
        } -ModuleName Scheduler

        Unregister-SnapCertSchedule -TaskName "SnapCert-AutoRenew"
        Should -Invoke Unregister-ScheduledTask -ModuleName Scheduler -Times 1
    }

    It "does not throw if task does not exist" {
        Mock Get-ScheduledTask { return $null } -ModuleName Scheduler
        { Unregister-SnapCertSchedule -TaskName "NonExistent" } | Should -Not -Throw
    }
}
```

- [ ] **Step 6.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/Scheduler.Tests.ps1 -Output Normal
```
Expected: FAIL

- [ ] **Step 6.3: Implement Scheduler module**

Create `src/modules/Scheduler.psm1`:
```powershell
function Register-SnapCertSchedule {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [string]$RunTime = "02:00",

        [string]$TaskName = "SnapCert-AutoRenew",

        [string]$TaskDescription = "SnapCert automatic certificate renewal check"
    )

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -Renew"

    $trigger = New-ScheduledTaskTrigger -Daily -At $RunTime

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
        -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description $TaskDescription -Force
}

function Unregister-SnapCertSchedule {
    param(
        [string]$TaskName = "SnapCert-AutoRenew"
    )

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
}

Export-ModuleMember -Function Register-SnapCertSchedule, Unregister-SnapCertSchedule
```

- [ ] **Step 6.4: Run tests to confirm they pass**

```powershell
Invoke-Pester tests/Scheduler.Tests.ps1 -Output Normal
```
Expected: `3 tests passed`

- [ ] **Step 6.5: Commit**

```powershell
git add src/modules/Scheduler.psm1 tests/Scheduler.Tests.ps1
git commit -m "feat: add Scheduler module for Windows Task Scheduler integration"
```

---

## Task 7: Main CLI Entry Point

**Files:**
- Create: `src/SnapCert.ps1`
- Create: `tests/SnapCert.Tests.ps1`

- [ ] **Step 7.1: Write failing CLI tests**

Create `tests/SnapCert.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"

    # Stub module functions so the script can be dot-sourced in tests
    function Write-SnapCertLog {}
    function Get-SnapCertConfig { return [PSCustomObject]@{
        DaysBeforeExpiry     = 30
        CertificateTemplates = @("Computer")
        CertStorePath        = "Cert:\LocalMachine\My"
        LogFilePath          = "$env:TEMP\snapcert_test.log"
        LogToEventLog        = $false
        EventLogSource       = "SnapCert"
        ScheduleTaskName     = "SnapCert-Test"
        ScheduleRunTime      = "02:00"
    }}
    function Get-ExpiringCertificates { return @() }
    function Invoke-CertificateRenewal { return [PSCustomObject]@{ Success = $true; Message = "ok" } }
    function Register-SnapCertSchedule {}
    function Unregister-SnapCertSchedule {}
}

Describe "SnapCert -Scan" {
    It "calls Get-ExpiringCertificates" {
        Mock Get-ExpiringCertificates { return @() } -Verifiable
        & "$PSScriptRoot/../src/SnapCert.ps1" -Scan
        Should -InvokeVerifiable
    }

    It "reports no certificates when store is empty" {
        Mock Get-ExpiringCertificates { return @() }
        $output = & "$PSScriptRoot/../src/SnapCert.ps1" -Scan 2>&1
        $output | Should -Match "No certificates"
    }
}

Describe "SnapCert -Renew with single template" {
    It "calls Invoke-CertificateRenewal for each expiring cert" {
        Mock Get-ExpiringCertificates { return @(New-MockCertificate) }
        Mock Invoke-CertificateRenewal { return [PSCustomObject]@{ Success = $true; Message = "ok" } } -Verifiable
        & "$PSScriptRoot/../src/SnapCert.ps1" -Renew
        Should -InvokeVerifiable
    }
}

Describe "SnapCert -Renew multi-template guard" {
    It "writes error and exits when more than one template is configured" {
        Mock Get-SnapCertConfig { return [PSCustomObject]@{
            DaysBeforeExpiry     = 30
            CertificateTemplates = @("Computer", "WebServer")
            CertStorePath        = "Cert:\LocalMachine\My"
            LogFilePath          = "$env:TEMP\snapcert_test.log"
            LogToEventLog        = $false
            EventLogSource       = "SnapCert"
            ScheduleTaskName     = "SnapCert-Test"
            ScheduleRunTime      = "02:00"
        }}
        { & "$PSScriptRoot/../src/SnapCert.ps1" -Renew -ErrorAction Stop } | Should -Throw
    }
}
```

- [ ] **Step 7.2: Run tests to confirm they fail**

```powershell
Invoke-Pester tests/SnapCert.Tests.ps1 -Output Normal
```
Expected: FAIL — script not found

- [ ] **Step 7.3: Implement SnapCert.ps1**

Create `src/SnapCert.ps1`:
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    SnapCert - Automated AD CS certificate renewal for domain-joined Windows machines.

.DESCRIPTION
    Scans the local machine certificate store for certificates expiring within
    a configured threshold and submits renewal requests to the AD CS CA.

.PARAMETER Scan
    Scan for expiring certificates and report. Does not renew.

.PARAMETER Renew
    Scan and renew any expiring certificates.

.PARAMETER Schedule
    Register SnapCert as a daily Windows Scheduled Task.

.PARAMETER Unschedule
    Remove the SnapCert Scheduled Task.

.PARAMETER DaysThreshold
    Override the configured days-before-expiry threshold for this run.

.PARAMETER DryRun
    Perform all steps except the actual certreq submission.

.PARAMETER ConfigPath
    Path to the SnapCert JSON config file.
#>
[CmdletBinding()]
param(
    [switch]$Scan,
    [switch]$Renew,
    [switch]$Schedule,
    [switch]$Unschedule,
    [int]$DaysThreshold = 0,
    [switch]$DryRun,
    [string]$ConfigPath = "C:\ProgramData\SnapCert\snapcert.json"
)

$moduleRoot = Join-Path $PSScriptRoot "modules"
Import-Module "$moduleRoot\Logging.psm1" -Force
Import-Module "$moduleRoot\Configuration.psm1" -Force
Import-Module "$moduleRoot\CertScanner.psm1" -Force
Import-Module "$moduleRoot\CertRenewal.psm1" -Force
Import-Module "$moduleRoot\Scheduler.psm1" -Force

$defaultConfigPath = Join-Path $PSScriptRoot "..\config\snapcert.default.json"
$config = Get-SnapCertConfig -ConfigPath $ConfigPath -DefaultConfigPath $defaultConfigPath

$logArgs = @{
    LogFilePath    = $config.LogFilePath
    LogToEventLog  = $config.LogToEventLog
    EventLogSource = $config.EventLogSource
}

$threshold = if ($DaysThreshold -gt 0) { $DaysThreshold } else { $config.DaysBeforeExpiry }

if ($Schedule) {
    Write-SnapCertLog -Message "Registering SnapCert scheduled task." -Level "INFO" @logArgs
    Register-SnapCertSchedule -ScriptPath $PSCommandPath -RunTime $config.ScheduleRunTime -TaskName $config.ScheduleTaskName
    Write-Host "Scheduled task '$($config.ScheduleTaskName)' registered at $($config.ScheduleRunTime) daily."
    exit 0
}

if ($Unschedule) {
    Unregister-SnapCertSchedule -TaskName $config.ScheduleTaskName
    Write-Host "Scheduled task '$($config.ScheduleTaskName)' removed."
    exit 0
}

if ($Scan -or $Renew) {
    Write-SnapCertLog -Message "Scanning for certificates expiring within $threshold days." -Level "INFO" @logArgs

    $expiring = foreach ($template in $config.CertificateTemplates) {
        Get-ExpiringCertificates -DaysThreshold $threshold -Template $template -CertStorePath $config.CertStorePath
    }

    if (-not $expiring) {
        Write-SnapCertLog -Message "No expiring certificates found." -Level "INFO" @logArgs
        Write-Host "No certificates expiring within $threshold days."
        exit 0
    }

    Write-Host "Found $($expiring.Count) certificate(s) expiring within $threshold days:"
    $expiring | Format-Table Subject, Thumbprint, NotAfter, DaysUntilExpiry -AutoSize

    if ($Renew) {
        # Multi-template per-cert routing is not yet implemented. Guard to prevent silent misuse.
        if ($config.CertificateTemplates.Count -gt 1) {
            Write-Error "SnapCert does not yet support renewal across multiple certificate templates in a single run. Configure a single template in CertificateTemplates. See docs for multi-template roadmap."
            exit 1
        }

        foreach ($cert in $expiring) {
            Write-SnapCertLog -Message "Enrolling new certificate for: $($cert.Subject) (expires $($cert.NotAfter))" -Level "INFO" @logArgs

            $result = Invoke-CertificateRenewal -Template $config.CertificateTemplates[0] -DryRun $DryRun.IsPresent
            if ($result.Success) {
                Write-SnapCertLog -Message "Enrollment succeeded: $($cert.Subject)" -Level "INFO" @logArgs
                Write-Host "[OK] Enrolled: $($cert.Subject)"
            } else {
                Write-SnapCertLog -Message "Enrollment failed: $($cert.Subject) — $($result.Message)" -Level "ERROR" @logArgs
                Write-Warning "[FAIL] $($cert.Subject): $($result.Message)"
            }
        }
    }
    exit 0
}

Write-Host @"
SnapCert - AD CS Certificate Renewal Tool

Usage:
  .\SnapCert.ps1 -Scan                    # Report expiring certificates
  .\SnapCert.ps1 -Renew                   # Scan and renew expiring certificates
  .\SnapCert.ps1 -Renew -DryRun           # Simulate renewal (no certreq calls)
  .\SnapCert.ps1 -Renew -DaysThreshold 14 # Override expiry threshold
  .\SnapCert.ps1 -Schedule                # Register daily scheduled task
  .\SnapCert.ps1 -Unschedule              # Remove scheduled task
"@
```

- [ ] **Step 7.4: Run CLI tests to confirm they pass**

```powershell
Invoke-Pester tests/SnapCert.Tests.ps1 -Output Normal
```
Expected: `4 tests passed`

- [ ] **Step 7.5: Manual smoke test on a domain-joined machine**

Run in a domain-joined PowerShell session:
```powershell
cd C:\Dev\SnapCert\src
.\SnapCert.ps1 -Scan
```
Expected: Either lists expiring certs, or prints "No certificates expiring within 30 days."

- [ ] **Step 7.6: Test DryRun mode**

```powershell
.\SnapCert.ps1 -Renew -DryRun
```
Expected: Scans, reports, and for each cert prints `[OK] Enrolled:` without calling certreq.

- [ ] **Step 7.7: Run full test suite**

```powershell
cd C:\Dev\SnapCert
Invoke-Pester tests/ -Output Normal
```
Expected: All tests pass.

- [ ] **Step 7.8: Commit**

```powershell
git add src/SnapCert.ps1 tests/SnapCert.Tests.ps1
git commit -m "feat: add main CLI entry point, wire all modules"
```

---

## Task 8: Final Push and Repo Cleanup

- [ ] **Step 8.1: Update README**

Update `README.md` with usage instructions, requirements, and how to run tests.

- [ ] **Step 8.2: Run full test suite one final time**

```powershell
Invoke-Pester tests/ -Output Normal
```
Expected: All tests pass.

- [ ] **Step 8.3: Push to GitHub**

```powershell
git push origin master
```

---

## Deferred (Post-MVP)

These were intentionally excluded from this plan and should be addressed in follow-up plans:

- **Deployment scope** (local vs centralized management server) — revisit once core tool is validated
- **Authentication strategy** (service accounts, credential profiles)
- **Multi-template per-cert routing** — config supports an array; a runtime guard in `SnapCert.ps1` currently rejects multi-template configs with an actionable error. To lift this, `Get-ExpiringCertificates` must return a `TemplateName` field and `Invoke-CertificateRenewal` must accept it per-cert
- **Targeted renewal by thumbprint** — current implementation does new enrollment (`certreq -new/-submit/-accept`), not targeted renewal of a specific cert. `certreq -renew` by thumbprint is the correct approach but requires a different INF structure and is deferred
- **`-WhatIf` / `SupportsShouldProcess` propagation** — `SnapCert.ps1` declares `[CmdletBinding()]` without `SupportsShouldProcess`; wiring `-WhatIf` through into module calls requires each module function to accept `ShouldProcess` and is deferred
- **Linux support** (certreq not available; ACME or openssl-based alternative needed)
- **Reporting / dashboard** — may drive decision on Python for a management layer
