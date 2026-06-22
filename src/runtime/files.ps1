function Get-CodexRtlLauncherScriptPath {
    Join-Path (Get-CodexRtlRuntimeRoot) 'launch-codex-rtl.vbs'
}

function Install-CodexRtlRuntimeFiles {
    param([Parameter(Mandatory)][string]$SourceRoot)

    $runtimeRoot = Get-CodexRtlRuntimeRoot
    $items = @(
        'patch.ps1',
        'src/shared/logging.ps1',
        'src/shared/prompting.ps1',
        'src/shared/asar.ps1',
        'src/codex/detection.ps1',
        'src/codex/rtl-payload.ps1',
        'src/runtime/state.ps1',
        'src/runtime/files.ps1',
        'src/runtime/shortcuts.ps1',
        'src/runtime/launch.ps1',
        'src/runtime/patching.ps1',
        'src/ui/menu.ps1'
    )

    foreach ($item in $items) {
        $source = Join-Path $SourceRoot $item
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Runtime source file not found: $source"
        }
        $destination = Join-Path $runtimeRoot $item
        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
        }
        $sourceFullPath = [System.IO.Path]::GetFullPath($source)
        $destinationFullPath = [System.IO.Path]::GetFullPath($destination)
        if ($sourceFullPath -ine $destinationFullPath) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }

    return $runtimeRoot
}

function New-CodexRtlLauncherScriptContent {
    param([Parameter(Mandatory)][string]$PatchScriptPath)

    $escapedPatchScriptPath = $PatchScriptPath.Replace('"', '""')
@"
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -LaunchCodexRtl"
shell.Run command, 0, False
"@
}

function Install-CodexRtlLauncherScript {
    param([Parameter(Mandatory)][string]$PatchScriptPath)

    $launcherPath = Get-CodexRtlLauncherScriptPath
    $launcherDir = Split-Path -Parent $launcherPath
    if (-not (Test-Path -LiteralPath $launcherDir)) {
        New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
    }
    New-CodexRtlLauncherScriptContent -PatchScriptPath $PatchScriptPath |
        Set-Content -LiteralPath $launcherPath -Encoding ASCII
    return $launcherPath
}

function Get-CodexRtlPatchScriptPath {
    if ($script:CodexRtlPatchScriptPath) { return $script:CodexRtlPatchScriptPath }
    if ($PSCommandPath) { return $PSCommandPath }
    return (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'patch.ps1')
}
