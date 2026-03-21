BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    Import-Module "$PSScriptRoot/../src/modules/CertScanner.psm1" -Force
}

Describe "Get-ExpiringCertificates" {
    It "returns certificates expiring within threshold" {
        $mockCerts = @(
            New-MockCertificate -DaysUntilExpiry 20
        )
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 1
    }

    It "excludes certificates not yet near expiry" {
        $mockCerts = @(
            New-MockCertificate -DaysUntilExpiry 60
        )
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 0
    }

    It "excludes certificates without private key" {
        $cert = New-MockCertificate -DaysUntilExpiry 10
        $cert.HasPrivateKey = $false
        Mock Get-ChildItem { return @($cert) } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result.Count | Should -Be 0
    }

    It "returns DaysUntilExpiry property on results" {
        $mockCerts = @(New-MockCertificate -DaysUntilExpiry 15)
        Mock Get-ChildItem { return $mockCerts } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result[0].DaysUntilExpiry | Should -BeLessOrEqual 15
    }

    It "returns empty array when no certificates match" {
        Mock Get-ChildItem { return @() } -ModuleName CertScanner

        $result = Get-ExpiringCertificates -DaysThreshold 30 -Template "Computer"
        $result | Should -BeNullOrEmpty
    }
}
