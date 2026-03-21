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
