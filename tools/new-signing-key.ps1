<#
.SYNOPSIS
    Generates the Codex RTL Fix maintainer RSA signing key.
.DESCRIPTION
    Creates an RSA-4096 private key in the same portable JSON format consumed
    by tools\sign-release.ps1. The private key is written outside the repository
    by default and must never be committed.
#>
param(
    [string]$KeyPath = (Join-Path $HOME ".codex-rtl-fix-signing.key"),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ((Test-Path -LiteralPath $KeyPath) -and (-not $Force)) {
    Write-Host "Private key already exists at: $KeyPath" -ForegroundColor Red
    Write-Host "Refusing to overwrite. Re-run with -Force only if you intentionally want to rotate keys." -ForegroundColor Yellow
    exit 1
}

$keyDir = Split-Path -Parent $KeyPath
if ($keyDir -and (-not (Test-Path -LiteralPath $keyDir))) {
    New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
}

$rsa = [System.Security.Cryptography.RSA]::Create(4096)
$params = $rsa.ExportParameters($true)

$privateObject = [ordered]@{
    Modulus = [Convert]::ToBase64String($params.Modulus)
    Exponent = [Convert]::ToBase64String($params.Exponent)
    D = [Convert]::ToBase64String($params.D)
    P = [Convert]::ToBase64String($params.P)
    Q = [Convert]::ToBase64String($params.Q)
    DP = [Convert]::ToBase64String($params.DP)
    DQ = [Convert]::ToBase64String($params.DQ)
    InverseQ = [Convert]::ToBase64String($params.InverseQ)
}

$publicObject = [ordered]@{
    Modulus = [Convert]::ToBase64String($params.Modulus)
    Exponent = [Convert]::ToBase64String($params.Exponent)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$privateJson = $privateObject | ConvertTo-Json -Compress
[IO.File]::WriteAllText($KeyPath, $privateJson, $utf8NoBom)

$publicJson = $publicObject | ConvertTo-Json -Compress
$publicBytes = [Text.Encoding]::UTF8.GetBytes($publicJson)
$publicB64 = [Convert]::ToBase64String($publicBytes)
$sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($publicBytes)
$fingerprint = ([BitConverter]::ToString($sha)).Replace('-', ':').ToLowerInvariant()

Write-Host "Private key written to: $KeyPath" -ForegroundColor Green
Write-Host "Public key fingerprint:"
Write-Host "  $fingerprint" -ForegroundColor Cyan
Write-Host "Public key for install.ps1:"
Write-Host "  $publicB64" -ForegroundColor Cyan
