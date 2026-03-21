# Shared helpers for SnapCert Pester tests

function New-MockCertificate {
    param(
        [int]$DaysUntilExpiry = 20,
        [string]$Subject = "CN=TESTMACHINE",
        [string]$Thumbprint = "AABBCCDD1122334455667788AABBCCDD11223344",
        [string]$TemplateName = "Computer"
    )

    $notAfter = (Get-Date).AddDays($DaysUntilExpiry)

    $mockExt = [PSCustomObject]@{
        Oid    = [PSCustomObject]@{ FriendlyName = "Certificate Template Name" }
        _value = $TemplateName
    }
    # Note: $t (multi-line flag) is intentionally ignored. CertScanner always calls Format($false).
    $mockExt | Add-Member -MemberType ScriptMethod -Name Format -Value { param($t) return $this._value } -Force

    return [PSCustomObject]@{
        Subject       = $Subject
        Thumbprint    = $Thumbprint
        NotAfter      = $notAfter
        HasPrivateKey = $true
        Extensions    = @($mockExt)
    }
}
