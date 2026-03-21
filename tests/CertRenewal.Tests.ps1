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

    It "INF Subject contains the FQDN as CN" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath -FQDN "srv01.corp.local" -ShortName "SRV01" -IPAddress "10.0.0.1"
        $content = Get-Content $infPath -Raw
        $content | Should -Match 'Subject = "CN=srv01\.corp\.local"'
        Remove-Item $infPath -Force
    }

    It "INF SAN includes the short name as DNS" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath -FQDN "srv01.corp.local" -ShortName "SRV01" -IPAddress "10.0.0.1"
        $content = Get-Content $infPath -Raw
        $content | Should -Match "dns=SRV01"
        Remove-Item $infPath -Force
    }

    It "INF SAN includes the FQDN as DNS" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath -FQDN "srv01.corp.local" -ShortName "SRV01" -IPAddress "10.0.0.1"
        $content = Get-Content $infPath -Raw
        $content | Should -Match "dns=srv01\.corp\.local"
        Remove-Item $infPath -Force
    }

    It "INF SAN includes the IP address" {
        $infPath = "$env:TEMP\test_renewal_$([System.Guid]::NewGuid().ToString('N')).inf"
        New-CertRenewalRequest -Template "Computer" -InfPath $infPath -FQDN "srv01.corp.local" -ShortName "SRV01" -IPAddress "10.0.0.1"
        $content = Get-Content $infPath -Raw
        $content | Should -Match "ipaddress=10\.0\.0\.1"
        Remove-Item $infPath -Force
    }
}

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
