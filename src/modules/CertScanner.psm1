function Get-ExpiringCertificates {
    param(
        [int]$DaysThreshold = 30,
        [string]$Template = "Computer",
        [string]$CertStorePath = "Cert:\LocalMachine\My"
    )

    $thresholdDate = (Get-Date).AddDays($DaysThreshold)

    $certs = Get-ChildItem -Path $CertStorePath |
        Where-Object { $_.HasPrivateKey -eq $true } |
        Where-Object { $_.NotAfter -lt $thresholdDate }

    if ($Template) {
        $certs = $certs | Where-Object {
            $_.Extensions | Where-Object {
                $_.Oid.FriendlyName -eq "Certificate Template Name" -and
                $_.Format($false) -eq $Template
            }
        }
    }

    return ,@($certs | Select-Object Subject, Thumbprint, NotAfter,
        @{N = "DaysUntilExpiry"; E = { [math]::Floor(($_.NotAfter - (Get-Date)).TotalDays) } })
}

Export-ModuleMember -Function Get-ExpiringCertificates
