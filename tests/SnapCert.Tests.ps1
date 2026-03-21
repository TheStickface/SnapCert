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
