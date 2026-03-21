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
            $lineDate = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd HH:mm:ss", $null)
            $lineDate -ge $cutoff
        } else {
            $true  # preserve lines that don't match the timestamp pattern
        }
    }

    if ($retained) {
        $retained | Set-Content $LogFilePath -Encoding UTF8
    } else {
        Clear-Content $LogFilePath
    }
}

Export-ModuleMember -Function Write-SnapCertLog, Invoke-SnapCertLogRotation
