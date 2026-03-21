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
