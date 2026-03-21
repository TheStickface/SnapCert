function Get-SnapCertConfig {
    param(
        [string]$ConfigPath = "C:\ProgramData\SnapCert\snapcert.json",
        [string]$DefaultConfigPath = "$PSScriptRoot\..\..\config\snapcert.default.json"
    )

    $defaults = Get-Content $DefaultConfigPath -Raw | ConvertFrom-Json

    if (-not (Test-Path $ConfigPath)) {
        return $defaults
    }

    $user = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    # Merge: user values override defaults, missing keys fall back to defaults
    $merged = $defaults.PSObject.Copy()
    foreach ($prop in $user.PSObject.Properties) {
        $merged.$($prop.Name) = $prop.Value
    }

    return $merged
}

function Save-SnapCertConfig {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$ConfigPath = "C:\ProgramData\SnapCert\snapcert.json"
    )

    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
}

Export-ModuleMember -Function Get-SnapCertConfig, Save-SnapCertConfig
