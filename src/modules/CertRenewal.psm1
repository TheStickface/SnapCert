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

Export-ModuleMember -Function New-CertRenewalRequest
