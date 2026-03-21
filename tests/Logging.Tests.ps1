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

Describe "Invoke-SnapCertLogRotation" {
    BeforeEach {
        $script:testLogPath = "$env:TEMP\snapcert_rotation_$([System.Guid]::NewGuid().ToString('N')).log"
    }
    AfterEach {
        if (Test-Path $script:testLogPath) { Remove-Item $script:testLogPath -Force }
    }

    It "removes lines older than retention period" {
        $oldDate = (Get-Date).AddDays(-91).ToString("yyyy-MM-dd HH:mm:ss")
        $newDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        @("$oldDate [INFO] old entry", "$newDate [INFO] new entry") | Set-Content $script:testLogPath

        Invoke-SnapCertLogRotation -LogFilePath $script:testLogPath -RetentionDays 90

        $lines = @(Get-Content $script:testLogPath)
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match "new entry"
    }

    It "retains lines within retention period" {
        $recentDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd HH:mm:ss")
        "$recentDate [INFO] recent entry" | Set-Content $script:testLogPath

        Invoke-SnapCertLogRotation -LogFilePath $script:testLogPath -RetentionDays 90

        $lines = Get-Content $script:testLogPath
        $lines.Count | Should -Be 1
    }

    It "does not throw if log file does not exist" {
        { Invoke-SnapCertLogRotation -LogFilePath "$env:TEMP\nonexistent_$([System.Guid]::NewGuid().ToString('N')).log" -RetentionDays 90 } | Should -Not -Throw
    }

    It "results in empty file when all lines are expired" {
        $oldDate = (Get-Date).AddDays(-100).ToString("yyyy-MM-dd HH:mm:ss")
        "$oldDate [INFO] old entry" | Set-Content $script:testLogPath

        Invoke-SnapCertLogRotation -LogFilePath $script:testLogPath -RetentionDays 90

        $lines = Get-Content $script:testLogPath -ErrorAction SilentlyContinue
        $lines | Should -BeNullOrEmpty
    }
}
