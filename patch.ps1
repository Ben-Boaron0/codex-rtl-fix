<#
.SYNOPSIS
    Codex RTL Fix
.DESCRIPTION
    Installs, restores, and inspects the local Codex Desktop RTL runtime.
#>
param(
    [string]$TrustedPubKey,
    [switch]$InspectCodex,
    [switch]$LaunchCodexRtl,
    [switch]$SkipMain
)

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$RequiresElevation = (-not $LaunchCodexRtl)
if ((-not $SkipMain) -and $RequiresElevation -and (-not $IsAdmin)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($InspectCodex) { $args += '-InspectCodex' }
        if ($TrustedPubKey) { $args += @('-TrustedPubKey', $TrustedPubKey) }
        Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $args
        Exit
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $InstallUrl = "https://raw.githubusercontent.com/Ben-Boaron0/codex-rtl-fix/main/install.ps1"
    Invoke-Expression (Invoke-RestMethod $InstallUrl)
    Exit
}

$script:CodexRtlFixModuleManifest = [ordered]@{
    'src/core/logging.ps1' = 'd13e9253a4c93ea497704450fa6541338d34aedbcb0dd73811a7d691c03a660c'
    'src/core/detection.ps1' = 'd13409ae3eb8c92079af4590797717d5c7cb4182b0298bcfbb7cec4d76d86ca9'
    'src/core/prompting.ps1' = '1f21230a4fc91d69a41e370d52768b02e70ab32d9f35fb64824c16ac0cc23202'
    'src/core/asar.ps1' = 'efff1c7b3a904d6d1dd6dc7b8a2a229b38a5c3ec69c32c8b35f1eb4143fb9a7b'
    'src/apps/codex/detection.ps1' = '79eedece45798244dcfd3008a9f1ac4f801ad69d267452b6718d145aa4cadab2'
    'src/apps/codex/inspection.ps1' = '49d80c53ccc219b153c4364b6c4a3dc13a95e3b5592ade3c39fb8ed15aa7f9d6'
    'src/apps/codex/rtl-payload.ps1' = 'c1020f6a9cbfa93475666a340232f929a821a40356d4bae56e434725b3ccba88'
    'src/apps/codex/runtime-rtl.ps1' = '5769ea397b2b53657f2ba76c87c21c9df552ac74f18d821df838990bee60bf0d'
    'src/ui/menu.ps1' = 'e778c708dd6d1239a91792f2db58f1258a7b809a86a40cafa0c51995356118cb'
}

foreach ($module in $script:CodexRtlFixModuleManifest.Keys) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $modulePath).Hash.ToLowerInvariant()
    $expectedHash = $script:CodexRtlFixModuleManifest[$module].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Required module hash mismatch: $module"
    }
    . $modulePath
}

$script:CodexRtlPatchScriptPath = $PSCommandPath
$script:AiRtlPatchScriptPath = $PSCommandPath

if ($SkipMain) {
    return
}

if ($InspectCodex) {
    Show-CodexInspection
    Exit
}

if ($LaunchCodexRtl) {
    Launch-CodexRtl
    Exit
}

Show-Menu
