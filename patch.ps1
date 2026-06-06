<#
.SYNOPSIS
    AI RTL Fix - Claude Desktop RTL Patcher
.DESCRIPTION
    Injects smart RTL support into desktop AI apps without breaking English/Code.
    Current adapter: Claude Desktop.
    Handles ASAR repackaging, executable hash patching, and cowork-svc binary certificate swapping.
    Strictly uses PURE BYTE-ARRAY manipulation matching the original Python script.
#>
param(
    [switch]$Auto,
    [string]$TrustedPubKey,
    [switch]$InspectCodex,
    [switch]$LaunchCodexRtl,
    [switch]$SkipMain
)

# Env-var fallback for `irm | iex` invocations where param binding is not possible.
if (-not $Auto -and $env:CLAUDE_RTL_AUTO -eq '1') { $Auto = $true }

# The trusted pubkey is passed as a PARAMETER, not an env var: environment
# variables set by install.ps1 / update.ps1 before Start-Process -Verb RunAs do
# NOT survive the UAC elevation boundary, so the elevated patch.ps1 would never
# see them and Save-TrustedPubkey would skip the pin. Mirror the param into the
# env var the rest of the script already reads.
if ($TrustedPubKey) { $env:CLAUDE_RTL_TRUSTED_PUBKEY = $TrustedPubKey }

# -----------------------------------------------------------------------------
# AUTO-ELEVATION: Request Administrator Privileges Automatically
# Supports both file execution and irm|iex piped execution
# -----------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$RequiresElevation = (-not $LaunchCodexRtl)
if ((-not $SkipMain) -and $RequiresElevation -and (-not $IsAdmin)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($Auto) { $args += '-Auto' }
        if ($InspectCodex) { $args += '-InspectCodex' }
        if ($TrustedPubKey) { $args += @('-TrustedPubKey', $TrustedPubKey) }
        Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $args
        Exit
    }

    # Prefer the locally-installed verified-update helper if it exists. That
    # helper (written admin-only at install time, see Save-UpdateScript) uses
    # the pinned pubkey to verify patch.ps1 before elevation -- hermetic
    # against a compromised GitHub repo. install.ps1 is unsigned, so falling
    # back to it is acceptable ONLY for first-time bootstrap where no local
    # trust anchor exists yet.
    $LocalUpdate = Join-Path $env:ProgramData "ClaudeRtlPatch\update.ps1"
    if (Test-Path $LocalUpdate) {
        if ($Auto) { $env:CLAUDE_RTL_AUTO = '1' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LocalUpdate
        Exit
    }
    # First-install bootstrap: no local pin yet. TOFU on install.ps1 -- the
    # same exposure the user already accepts when running `irm install.ps1 | iex`.
    # PS 5.1 defaults to TLS 1.0; GitHub requires 1.2+ -- enable it before the
    # IRM call below or the fallback fails with an opaque connection error.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $InstallUrl = "https://raw.githubusercontent.com/Ben-Boaron0/ai-rtl-fix/main/install.ps1"
    if ($Auto) { $env:CLAUDE_RTL_AUTO = '1' }
    Invoke-Expression (Invoke-RestMethod $InstallUrl)
    Exit
}

# -----------------------------------------------------------------------------
# MODULE LOADING
# -----------------------------------------------------------------------------
$moduleRoot = Join-Path $PSScriptRoot 'src'
$modules = @(
    'core/logging.ps1',
    'core/detection.ps1',
    'core/asar.ps1',
    'apps/claude/payload.ps1',
    'apps/claude/state.ps1',
    'apps/claude/detection.ps1',
    'apps/codex/detection.ps1',
    'apps/codex/inspection.ps1',
    'apps/codex/rtl-payload.ps1',
    'apps/codex/runtime-rtl.ps1',
    'apps/claude/patching.ps1',
    'ui/menu.ps1'
)

foreach ($module in $modules) {
    $modulePath = Join-Path $moduleRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    . $modulePath
}

$script:AiRtlPatchScriptPath = $PSCommandPath

# Start the application
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

if ($Auto) {
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "  AUTO RE-PATCH MODE (triggered by Claude update)" -ForegroundColor Cyan
    Write-Host "=======================================================`n" -ForegroundColor Cyan
    $exitCode = 0
    try {
        Install-Patch
    } catch {
        Write-Host "`n[!] Auto patch failed: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }

    Write-Host "`nPress Enter to close this window..." -ForegroundColor DarkGray
    $null = Read-Host
    Exit $exitCode
} else {
    Show-Menu
}
