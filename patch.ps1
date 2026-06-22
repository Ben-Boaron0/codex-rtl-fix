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
    'src/shared/logging.ps1' = '145acb1e07998a2944a01d22abd8e7438751b16db70f256d2b6146126e0e5985'
    'src/shared/prompting.ps1' = '1f21230a4fc91d69a41e370d52768b02e70ab32d9f35fb64824c16ac0cc23202'
    'src/shared/asar.ps1' = 'efff1c7b3a904d6d1dd6dc7b8a2a229b38a5c3ec69c32c8b35f1eb4143fb9a7b'
    'src/codex/detection.ps1' = '9a8aa5aa1ed0c0e582b862f89164400bfd25db132fd4d0800e3517316a81bd74'
    'src/codex/rtl-payload.ps1' = 'f5236e71f33ecd3c04a0810ffc09da727f96e5f9f3468d0be8b5e5387fa99da0'
    'src/runtime/state.ps1' = 'f90b0395867042b49adfed6c5aa4148df5556f720ed5c71f7c848d9cb89400f7'
    'src/runtime/files.ps1' = '533eba5784f67e3d9c2deac160bae9e3f103ca96ccc177368dd4f1c48359d75e'
    'src/runtime/shortcuts.ps1' = 'c80f64448d722dd5cb244c4debf22492ccfdbc2091b4bfad1ab58184c9ca95da'
    'src/runtime/launch.ps1' = 'b6ba9f49a2dc041343984c18e4c36e1acf08259a8843b88c56abbc52472fe7ed'
    'src/runtime/patching.ps1' = 'f0360a2bec460a9b5a88f67282f2cd14f5139b2d3660705ad4ba78bb1057b258'
    'src/ui/menu.ps1' = '0f391ea9ae8a1dce913e3ad25b733c000527e595cfd3bc78961712a81ea2b31f'
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
