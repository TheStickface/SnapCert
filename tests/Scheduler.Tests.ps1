BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Scheduler.psm1" -Force
}

Describe "Register-SnapCertSchedule" {
    BeforeAll {
        Mock Register-ScheduledTask { return $null } -ModuleName Scheduler
        Mock New-ScheduledTaskAction { [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_TaskAction') } -ModuleName Scheduler
        Mock New-ScheduledTaskTrigger { [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_TaskTrigger') } -ModuleName Scheduler
        Mock New-ScheduledTaskPrincipal { [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_TaskPrincipal') } -ModuleName Scheduler
        Mock New-ScheduledTaskSettingsSet { [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_TaskSettings') } -ModuleName Scheduler
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
