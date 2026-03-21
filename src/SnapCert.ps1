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

if ($Renew -and $config.CertificateTemplates.Count -gt 1) {
    throw "SnapCert does not yet support renewal across multiple certificate templates in a single run. Configure a single template in CertificateTemplates. See docs for multi-template roadmap."
}

if ($Scan -or $Renew) {
    Write-SnapCertLog -Message "Scanning for certificates expiring within $threshold days." -Level "INFO" @logArgs

    $expiring = foreach ($template in $config.CertificateTemplates) {
        Get-ExpiringCertificates -DaysThreshold $threshold -Template $template -CertStorePath $config.CertStorePath
    }

    if (-not $expiring) {
        Write-SnapCertLog -Message "No expiring certificates found." -Level "INFO" @logArgs
        Write-Output "No certificates expiring within $threshold days."
        exit 0
    }

    Write-Host "Found $($expiring.Count) certificate(s) expiring within $threshold days:"
    $expiring | Format-Table Subject, Thumbprint, NotAfter, DaysUntilExpiry -AutoSize

    if ($Renew) {

        foreach ($cert in $expiring) {
            Write-SnapCertLog -Message "Enrolling new certificate for: $($cert.Subject) (expires $($cert.NotAfter))" -Level "INFO" @logArgs

            $result = Invoke-CertificateRenewal -Template $config.CertificateTemplates[0] -DryRun $DryRun.IsPresent
            if ($result.Success) {
                Write-SnapCertLog -Message "Enrollment succeeded: $($cert.Subject)" -Level "INFO" @logArgs
                Write-Host "[OK] Enrolled: $($cert.Subject)"
            } else {
                Write-SnapCertLog -Message "Enrollment failed: $($cert.Subject) - $($result.Message)" -Level "ERROR" @logArgs
                Write-Warning "[FAIL] $($cert.Subject): $($result.Message)"
            }
        }
    }
    exit 0
}

Write-Host "SnapCert - AD CS Certificate Renewal Tool"
Write-Host ""
Write-Host "Usage:"
Write-Host "  .\SnapCert.ps1 -Scan                    # Report expiring certificates"
Write-Host "  .\SnapCert.ps1 -Renew                   # Scan and renew expiring certificates"
Write-Host "  .\SnapCert.ps1 -Renew -DryRun           # Simulate renewal (no certreq calls)"
Write-Host "  .\SnapCert.ps1 -Renew -DaysThreshold 14 # Override expiry threshold"
Write-Host "  .\SnapCert.ps1 -Schedule                # Register daily scheduled task"
Write-Host "  .\SnapCert.ps1 -Unschedule              # Remove scheduled task"
