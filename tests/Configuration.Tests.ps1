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
