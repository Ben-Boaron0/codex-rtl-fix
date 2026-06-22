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
    'src/shared/logging.ps1' = '1d250837c0f59119b684933a7e81d6e4f02fb0e632c532869f5e58f54c9a74d2'
    'src/shared/prompting.ps1' = '7b443a60b0f87c15ef6d7ecd5f9130fcb8acdaf24763af1e1feb7874678e0c1f'
    'src/shared/asar.ps1' = 'f85da3d285c27117c6a9504a60dd060cd4b1080d28e7655c7e92e3a84ad4f3f2'
    'src/codex/detection.ps1' = 'b3a2f5fdeca81dea966820fc4a0daa0842ca7cd9c52d98f8a553b1311985a19d'
    'src/codex/rtl-payload.ps1' = 'f26467299b4a2504406f5ad9dc9599fcec9331bb6239a191458a116876cb7048'
    'src/runtime/state.ps1' = '2cc8f625507caa95ed4c8c1e647ee973d7125015feaa754eab9063fb0d7fad55'
    'src/runtime/files.ps1' = 'aa41d91c1095710cd22826361437c7c59647f0d57924f897f1cef788f221e011'
    'src/runtime/shortcuts.ps1' = '23ed7f69f0321c51b52605947e6e78b6d3ffd5110f16f6808eba8c7ff802d54b'
    'src/runtime/launch.ps1' = '4bc83ca6d063154dfa13db6c2626805b7a39b585f397c39368fd3cf3fa7ef5e3'
    'src/runtime/patching.ps1' = 'a7c9bd494d70ad2668ee399a828148bd9a25149e78884dda9f46deb61a230e79'
    'src/ui/menu.ps1' = '7b1fcf4368e25b6f381f445a31ef238fab2d3b263397f3e22f64a488dcaf254d'
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
