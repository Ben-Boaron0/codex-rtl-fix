<#
.SYNOPSIS
    Codex RTL Fix
.DESCRIPTION
    Installs and restores the local Codex Desktop RTL runtime.
#>
param(
    [string]$TrustedPubKey,
    [switch]$LaunchCodexRtl,
    [switch]$SkipMain
)

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$RequiresElevation = (-not $LaunchCodexRtl)
if ((-not $SkipMain) -and $RequiresElevation -and (-not $IsAdmin)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
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
    'src/shared/logging.ps1' = 'e4939b8b239036459e3b59429ae62590de53cbf51b9c22bec1a262938b1223a4'
    'src/shared/prompting.ps1' = '1f21230a4fc91d69a41e370d52768b02e70ab32d9f35fb64824c16ac0cc23202'
    'src/shared/asar.ps1' = 'efff1c7b3a904d6d1dd6dc7b8a2a229b38a5c3ec69c32c8b35f1eb4143fb9a7b'
    'src/codex/detection.ps1' = 'b3a2f5fdeca81dea966820fc4a0daa0842ca7cd9c52d98f8a553b1311985a19d'
    'src/codex/rtl-payload.ps1' = 'f54f9ac96316b6fa4a53d831f249dbb54860c2918234cd23da32e08a0caaf712'
    'src/runtime/state.ps1' = '490d408bafc1de898c7d950abc12961185b57633303289e2448936f61fcc0c22'
    'src/runtime/files.ps1' = 'ed7edfae4c79d6e58becbef2eaa0fb3494aabe28fb69e280064087b0dfa7244e'
    'src/runtime/shortcuts.ps1' = '39a7445dddf44b5946a023360fbcb08c3148dca23677b4309e4f3260aa5d0ffc'
    'src/runtime/launch.ps1' = '82d9a2fa318a07d8aea6f716c68c18ccf18e178ce8b4f1572e2c9177ad86c199'
    'src/runtime/patching.ps1' = '61de687559c7bdb176c993ccf7440680a11a4693d09e2bdb154f0c9ed0f8c001'
    'src/ui/menu.ps1' = 'bedb04b7a7e1f9a45ba8001fe35b606a6354adf4917cc7d7cc8cfa27253c4d64'
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

if ($SkipMain) {
    return
}

if ($LaunchCodexRtl) {
    Launch-CodexRtl
    Exit
}

Show-Menu
