# Codex RTL Fix -- verified installer.
#
# Downloads patch.ps1 and patch.ps1.sig from GitHub, verifies the signature
# against an RSA-4096 public key hardcoded below, then elevates to install.
#
# A compromised GitHub repository alone is NOT enough to ship malicious code to
# users -- the attacker would also need the maintainer's offline private key.
#
# Public-key fingerprint (SHA-256 over the embedded JSON blob below):
#   dc:6e:f8:65:eb:3c:00:46:76:98:3b:35:9c:77:1e:ba:31:70:4b:5f:fc:c2:b2:3e:5f:4a:d3:46:44:84:7b:1f
$ExpectedPubKey = 'eyJNb2R1bHVzIjoiMmI1bHhCYVl5T3Z6ZGdDaHFMTEhGbkFCbGIreXhvRFo3ODRJa0FjQjNOSDFLb2IzQW9JM2xUeS9RaHNHd1lrMDJodnZrejFVb1B0Q3RMalZwZ2EraXRiR3lJMDRZUXRZbDQ2ZXJtbjV1NWhBNk9leUsySi9CRkVjUTkzamlpOVdFYlVQWTM4VCtDcGE3Mk96eFk2OVJ4bjNreksxS01ULzhXOHQ0RFJNWFZpMmxreEw2TXRuUHRKRkJDaW42R0p0RWc2QWt2OERMTmM1VVVtLzdOL0t3S0hTbS85V0MvcmE4ditwbG9RbENQdEEwNUNpMjVpWFk3aE9uSGsyVWk5YTNKbjFDNUZPajhPdFJlV1lUenExbVRVMUpZdXlRYjA5ZGtyNXJSMWovK1htVkdySzMyQ2p6Qm5wY3dPUUtmZFdwbjNzUGttMDBWbDVLeVYwZXFTaHpoL0Z2bjhCa2hWTEczb3NHMkwvbHNGN3AybkxYTTJVOC9KVkRpYXVLdStEb1czWmxoSUpmOGsydTYrTkxtMFdXUzZQdkhLZldXMElNY0JLMVl4L09rQTVZUTI5dW83eTU0WENjUnZBSGMwa01SZHkwbEdsdkIwMWs2T2ZKeitiaEdkUWt5NVZadDdzYVRqUEJkcVBBVjducnBRYU9UdU9hL29XUGZlRWJ3aXJIcDU5UUl6eFJkenVOUkk4Q2R6enMxVXB2TTc5cm4zZHZraHVCNG1WY2RBMi9IUlJXVHJySWM0d0hrZ1lteCtUTngrTjFNNFloZEdHQkJ3bFlySUFWWTQ5MU1GcG9KUnFJNSszNndkNHJySDB3eGdNR2p4cmZIcjBWOHg0ZjZzUFNWSWdiaFp5MG41Ni9NNjl1Sk9FdDBmMmhxN3htMVN4T004TXZOV2ptM0U9IiwiRXhwb25lbnQiOiJBUUFCIn0='

$RepoBase = 'https://raw.githubusercontent.com/Ben-Boaron0/codex-rtl-fix/main'
$TmpRoot  = Join-Path $env:TEMP 'codex_rtl_fix_patch'
$TmpFile  = Join-Path $TmpRoot 'patch.ps1'
$ModuleFiles = @(
    'src/core/logging.ps1',
    'src/core/detection.ps1',
    'src/core/prompting.ps1',
    'src/core/asar.ps1',
    'src/apps/codex/detection.ps1',
    'src/apps/codex/inspection.ps1',
    'src/apps/codex/rtl-payload.ps1',
    'src/apps/codex/runtime-rtl.ps1',
    'src/ui/menu.ps1'
)

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$client = New-Object System.Net.WebClient
try {
    $patchBytes = $client.DownloadData("$RepoBase/patch.ps1")
    $sigB64     = $client.DownloadString("$RepoBase/patch.ps1.sig").Trim()
} catch {
    Write-Host ""
    Write-Host "Network error downloading patch: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check connectivity and retry." -ForegroundColor Yellow
    return
}

try {
    $pubJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ExpectedPubKey))
    $pubObj  = $pubJson | ConvertFrom-Json
    $params = New-Object System.Security.Cryptography.RSAParameters
    $params.Modulus  = [Convert]::FromBase64String($pubObj.Modulus)
    $params.Exponent = [Convert]::FromBase64String($pubObj.Exponent)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportParameters($params)
} catch {
    Write-Host "Internal error: bundled public key is malformed ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Do NOT proceed -- this means install.ps1 itself was tampered with." -ForegroundColor Red
    return
}

try {
    $sigBytes = [Convert]::FromBase64String($sigB64)
} catch {
    Write-Host ""
    Write-Host "Downloaded signature is not valid base64. Aborting." -ForegroundColor Red
    return
}

$valid = $rsa.VerifyData(
    $patchBytes, $sigBytes,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

if (-not $valid) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  SIGNATURE VERIFICATION FAILED -- REFUSING TO RUN patch.ps1     " -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "The downloaded patch does not match the maintainer's signature." -ForegroundColor Yellow
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  * The GitHub repository was compromised." -ForegroundColor Yellow
    Write-Host "  * Your network or proxy is intercepting traffic." -ForegroundColor Yellow
    Write-Host "  * A maintainer pushed patch.ps1 without re-signing." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Cross-check the public-key fingerprint at:" -ForegroundColor Cyan
    Write-Host "  https://github.com/Ben-Boaron0/codex-rtl-fix#verification" -ForegroundColor Cyan
    return
}

$content = [System.Text.Encoding]::UTF8.GetString($patchBytes)
if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }

try {
    if (-not (Test-Path -LiteralPath $TmpRoot)) {
        New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
    }

    foreach ($module in $ModuleFiles) {
        $moduleBytes = $client.DownloadData("$RepoBase/$module")
        $modulePath = Join-Path $TmpRoot $module
        $moduleDir = Split-Path -Parent $modulePath
        if (-not (Test-Path -LiteralPath $moduleDir)) {
            New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null
        }
        [System.IO.File]::WriteAllBytes($modulePath, $moduleBytes)
    }
} catch {
    Write-Host ""
    Write-Host "Network error downloading required modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check connectivity and retry." -ForegroundColor Yellow
    return
}

[System.IO.File]::WriteAllText($TmpFile, $content, [System.Text.UTF8Encoding]::new($true))

Write-Host "Codex RTL Fix verified ($($patchBytes.Length) bytes) and modules downloaded. Elevating..." -ForegroundColor Green

Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$TmpFile`" -TrustedPubKey `"$ExpectedPubKey`""
