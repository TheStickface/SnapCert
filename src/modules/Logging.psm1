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
        try {
            $eventType = switch ($Level) {
                "ERROR"   { "Error" }
                "WARNING" { "Warning" }
                default   { "Information" }
            }
            if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
                New-EventLog -LogName Application -Source $EventLogSource -ErrorAction Stop
            }
            Write-EventLog -LogName Application -Source $EventLogSource -EventId 1000 -EntryType $eventType -Message $Message
        } catch {
            # Event Log write failed (e.g. restricted ACL on hardened host). File log entry already written — non-fatal.
            Write-Warning "SnapCert: Could not write to Windows Event Log: $_"
        }
    }
}

function Invoke-SnapCertLogRotation {
    param(
        [string]$LogFilePath = "C:\ProgramData\SnapCert\snapcert.log",
        [int]$RetentionDays = 90
    )

    if (-not (Test-Path $LogFilePath)) { return }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $lines = Get-Content $LogFilePath

    $retained = $lines | Where-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            $lineDate = [datetime]::MinValue
            if ([datetime]::TryParseExact($Matches[1], "yyyy-MM-dd HH:mm:ss", $null, [System.Globalization.DateTimeStyles]::None, [ref]$lineDate)) {
                $lineDate -ge $cutoff
            } else {
                $true  # unparseable timestamp — preserve the line
            }
        } else {
            $true  # no timestamp prefix — preserve the line
        }
    }

    $tempPath = "$LogFilePath.tmp"
    try {
        if ($retained) {
            $retained | Set-Content $tempPath -Encoding UTF8
        } else {
            Set-Content $tempPath -Value $null -Encoding UTF8
        }
        Move-Item -Path $tempPath -Destination $LogFilePath -Force
    } finally {
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function Write-SnapCertLog, Invoke-SnapCertLogRotation
