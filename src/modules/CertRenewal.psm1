function New-CertRenewalRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [string]$InfPath = "$env:TEMP\snapcert_renewal.inf",

        [int]$KeyLength = 2048
    )

    $inf = @"
[Version]
Signature = "`$Windows NT`$"

[NewRequest]
Subject = ""
MachineKeySet = TRUE
KeyLength = $KeyLength
KeySpec = 1
Exportable = FALSE
RequestType = PKCS10

[RequestAttributes]
CertificateTemplate = $Template
"@

    $inf | Out-File -FilePath $InfPath -Encoding ASCII
}

function Invoke-CertificateRenewal {
    param(
        [string]$Template = "Computer",
        [bool]$DryRun = $false,
        [string]$WorkDir = $env:TEMP
    )

    if ($DryRun) {
        return [PSCustomObject]@{ Success = $true; Message = "DryRun: skipped certreq execution" }
    }

    $infPath = Join-Path $WorkDir "snapcert_renewal.inf"
    $reqPath = Join-Path $WorkDir "snapcert_renewal.req"
    $cerPath = Join-Path $WorkDir "snapcert_renewal.cer"

    New-CertRenewalRequest -Template $Template -InfPath $infPath

    # Stage 1: Generate CSR
    $newResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-new -q `"$infPath`" `"$reqPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($newResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -new failed (exit $($newResult.ExitCode))" }
    }

    # Stage 2: Submit to CA
    $submitResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-submit -q `"$reqPath`" `"$cerPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($submitResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -submit failed (exit $($submitResult.ExitCode))" }
    }

    # Stage 3: Accept and install certificate
    $acceptResult = Start-Process -FilePath "certreq.exe" -ArgumentList "-accept `"$cerPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($acceptResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Message = "certreq -accept failed (exit $($acceptResult.ExitCode))" }
    }

    # Cleanup temp files
    @($infPath, $reqPath, $cerPath) | Where-Object { Test-Path $_ } | Remove-Item -Force

    return [PSCustomObject]@{ Success = $true; Message = "Certificate enrolled successfully" }
}

Export-ModuleMember -Function New-CertRenewalRequest, Invoke-CertificateRenewal
