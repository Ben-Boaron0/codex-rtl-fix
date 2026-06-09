function Get-CodexRtlStateRoot {
    Join-Path $env:LOCALAPPDATA 'AI RTL Fix\Codex'
}

function Get-AiRtlRuntimeRoot {
    Join-Path $env:LOCALAPPDATA 'AI RTL Fix\runtime'
}

function Get-CodexRtlStatePath {
    Join-Path (Get-CodexRtlStateRoot) 'state.json'
}

function Get-CodexRtlWorkingDirectory {
    $root = Get-CodexRtlStateRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    return $root
}

function Get-CodexRtlShortcutPath {
    Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex RTL.lnk'
}

function Get-CodexRtlLegacyShortcutPath {
    Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex.lnk'
}

function Get-CodexRtlLauncherScriptPath {
    Join-Path (Get-AiRtlRuntimeRoot) 'launch-codex-rtl.vbs'
}

function Get-CodexShortcutBackupRoot {
    Join-Path (Get-CodexRtlStateRoot) 'backups\shortcuts'
}

function Get-CodexRtlDefaultPort {
    18317
}

function Test-TcpPortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Get-CodexRtlAvailablePort {
    $start = Get-CodexRtlDefaultPort
    for ($port = $start; $port -lt ($start + 50); $port++) {
        if (Test-TcpPortAvailable -Port $port) { return $port }
    }
    return $start
}

function New-CodexRtlLaunchArguments {
    param([Parameter(Mandatory)][int]$Port)

    @(
        "--remote-debugging-port=$Port",
        '--remote-debugging-address=127.0.0.1'
    )
}

function Install-AiRtlRuntimeFiles {
    param([Parameter(Mandatory)][string]$SourceRoot)

    $runtimeRoot = Get-AiRtlRuntimeRoot
    $items = @(
        'patch.ps1',
        'src/core/logging.ps1',
        'src/core/detection.ps1',
        'src/core/asar.ps1',
        'src/apps/claude/payload.ps1',
        'src/apps/claude/state.ps1',
        'src/apps/claude/detection.ps1',
        'src/apps/codex/detection.ps1',
        'src/apps/codex/inspection.ps1',
        'src/apps/codex/rtl-payload.ps1',
        'src/apps/codex/runtime-rtl.ps1',
        'src/apps/claude/patching.ps1',
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

function Get-CodexShortcutSearchRoots {
    @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
}

function Get-ShortcutDetails {
    param([Parameter(Mandatory)][string]$Path)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    [pscustomobject]@{
        TargetPath = [string]$shortcut.TargetPath
        Arguments = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        IconLocation = [string]$shortcut.IconLocation
    }
}

function Test-FileWritable {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-CodexShortcutInventory {
    $rows = @()
    foreach ($root in Get-CodexShortcutSearchRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.lnk' -Force -ErrorAction SilentlyContinue) {
            $details = $null
            try { $details = Get-ShortcutDetails -Path $item.FullName } catch { }
            $rows += [pscustomobject]@{
                Path = $item.FullName
                Name = $item.Name
                Exists = $true
                IsLink = ($item.Extension -ieq '.lnk')
                IsWritable = Test-FileWritable -Path $item.FullName
                TargetPath = if ($details) { $details.TargetPath } else { '' }
                Arguments = if ($details) { $details.Arguments } else { '' }
                WorkingDirectory = if ($details) { $details.WorkingDirectory } else { '' }
                IconLocation = if ($details) { $details.IconLocation } else { '' }
            }
        }
    }
    $rows
}

function Test-CodexShortcutReplaceable {
    param([Parameter(Mandatory)]$Shortcut)

    if (-not $Shortcut.Exists -or -not $Shortcut.IsLink -or -not $Shortcut.IsWritable) { return $false }
    $haystack = @($Shortcut.Name, $Shortcut.TargetPath, $Shortcut.Arguments) -join "`n"
    return [bool]($haystack -match 'OpenAI\.Codex|\\Codex\.exe|(^|[^A-Za-z])Codex([^A-Za-z]|$)')
}

function Test-CodexShortcutCandidate {
    param([Parameter(Mandatory)]$Shortcut)

    if (-not $Shortcut.IsLink) { return $false }
    $haystack = @($Shortcut.Name, $Shortcut.TargetPath, $Shortcut.Arguments) -join "`n"
    return [bool]($haystack -match 'OpenAI\.Codex|\\Codex\.exe|(^|[^A-Za-z])Codex([^A-Za-z]|$)')
}

function Test-CodexShortcutSeedable {
    param([Parameter(Mandatory)]$Shortcut)

    if (-not $Shortcut.Exists -or -not $Shortcut.IsLink -or -not $Shortcut.IsWritable) { return $false }
    return (Test-CodexShortcutCandidate -Shortcut $Shortcut)
}

function Get-CodexSiblingRtlShortcutPath {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    $shortcutDir = Split-Path -Parent $ShortcutPath
    Join-Path $shortcutDir 'Codex RTL.lnk'
}

function Get-StableShortcutBackupPath {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($ShortcutPath.ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    Join-Path (Get-CodexShortcutBackupRoot) "$hash.lnk"
}

function New-CodexShortcutBackupRecord {
    param(
        [Parameter(Mandatory)]$Shortcut,
        [Parameter(Mandatory)][string]$BackupPath,
        [string]$Kind = 'Shortcut'
    )

    [pscustomobject]@{
        OriginalPath = $Shortcut.Path
        BackupPath = $BackupPath
        OriginalTargetPath = $Shortcut.TargetPath
        OriginalArguments = $Shortcut.Arguments
        Kind = $Kind
        ReplacedAt = [DateTimeOffset]::Now.ToString('o')
    }
}

function Backup-CodexShortcut {
    param([Parameter(Mandatory)]$Shortcut)

    $backupPath = Get-StableShortcutBackupPath -ShortcutPath $Shortcut.Path
    $backupDir = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }
    Copy-Item -LiteralPath $Shortcut.Path -Destination $backupPath -Force
    New-CodexShortcutBackupRecord -Shortcut $Shortcut -BackupPath $backupPath -Kind 'Shortcut'
}

function Get-CodexIconLocation {
    param($Inspection)

    if ($Inspection -and $Inspection.InstallLocation) {
        $icon = Join-Path $Inspection.InstallLocation 'app\resources\icon.ico'
        if (Test-Path -LiteralPath $icon) { return $icon }
    }
    if ($Inspection -and $Inspection.AppExe) {
        return "$($Inspection.AppExe),0"
    }
    return "$env:SystemRoot\System32\shell32.dll,167"
}

function New-CodexLauncherShortcutSpec {
    param($Inspection = $null)

    $launcherScript = Get-CodexRtlLauncherScriptPath
    [pscustomobject]@{
        TargetPath = "$env:SystemRoot\System32\wscript.exe"
        Arguments = "`"$launcherScript`""
        WorkingDirectory = Get-CodexRtlWorkingDirectory
        IconLocation = Get-CodexIconLocation -Inspection $Inspection
    }
}

function New-CodexLauncherShortcut {
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)]$Spec
    )

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        New-Item -ItemType Directory -Force -Path $shortcutDir | Out-Null
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $Spec.TargetPath
    $shortcut.Arguments = $Spec.Arguments
    $shortcut.IconLocation = $Spec.IconLocation
    $shortcut.WorkingDirectory = $Spec.WorkingDirectory
    $shortcut.Save()
}

function Test-CodexRtlOwnedShortcut {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    if (-not (Test-Path -LiteralPath $ShortcutPath)) { return $false }
    try {
        $details = Get-ShortcutDetails -Path $ShortcutPath
        return ($details.TargetPath -like '*\wscript.exe' -and
            $details.Arguments -like '*launch-codex-rtl.vbs*')
    } catch {
        return $false
    }
}

function Remove-CodexRtlOwnedShortcut {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    if (Test-CodexRtlOwnedShortcut -ShortcutPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        return $true
    }
    return $false
}

function Replace-CodexShortcut {
    param(
        [Parameter(Mandatory)]$Shortcut,
        [Parameter(Mandatory)]$Spec
    )

    $backup = Backup-CodexShortcut -Shortcut $Shortcut
    New-CodexLauncherShortcut -ShortcutPath $Shortcut.Path -Spec $Spec
    return $backup
}

function New-CodexParallelRtlShortcut {
    param(
        [Parameter(Mandatory)]$SourceShortcut,
        [Parameter(Mandatory)]$Spec
    )

    $rtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $SourceShortcut.Path
    New-CodexLauncherShortcut -ShortcutPath $rtlShortcutPath -Spec $Spec
    return $rtlShortcutPath
}

function Install-CodexParallelRtlShortcutIfPossible {
    param(
        [Parameter(Mandatory)]$SourceShortcut,
        [Parameter(Mandatory)]$Spec
    )

    if (-not (Test-CodexShortcutSeedable -Shortcut $SourceShortcut)) {
        return $false
    }

    $rtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $SourceShortcut.Path
    if (Test-Path -LiteralPath $rtlShortcutPath) {
        if (-not (Test-CodexRtlOwnedShortcut -ShortcutPath $rtlShortcutPath)) {
            return $false
        }
    }

    New-CodexParallelRtlShortcut -SourceShortcut $SourceShortcut -Spec $Spec | Out-Null
    return $true
}

function Install-CodexStartMenuRtlShortcut {
    param([Parameter(Mandatory)]$Spec)

    $shortcutPath = Get-CodexRtlShortcutPath
    if (Test-Path -LiteralPath $shortcutPath) {
        if (-not (Test-CodexRtlOwnedShortcut -ShortcutPath $shortcutPath)) {
            return $false
        }
    }

    New-CodexLauncherShortcut -ShortcutPath $shortcutPath -Spec $Spec
    return $true
}

function Restore-CodexShortcutBackups {
    param([object[]]$Backups)

    $restored = @()
    foreach ($backup in @($Backups)) {
        if (-not $backup.BackupPath -or -not $backup.OriginalPath) { continue }
        if (-not (Test-Path -LiteralPath $backup.BackupPath)) {
            Write-Warn "Codex shortcut backup missing: $($backup.BackupPath)"
            continue
        }
        try {
            $targetDir = Split-Path -Parent $backup.OriginalPath
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            Copy-Item -LiteralPath $backup.BackupPath -Destination $backup.OriginalPath -Force
            $restored += $backup
        } catch {
            Write-Warn "Codex shortcut restore failed for $($backup.OriginalPath): $($_.Exception.Message)"
        }
    }
    $restored
}

function Get-CodexRtlPatchScriptPath {
    if ($script:AiRtlPatchScriptPath) { return $script:AiRtlPatchScriptPath }
    if ($PSCommandPath) { return $PSCommandPath }
    return (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'patch.ps1')
}

function Read-CodexRtlState {
    $path = Get-CodexRtlStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $ownedArtifacts = @()
        if ($state.PSObject.Properties.Name -contains 'OwnedArtifacts') {
            $ownedArtifacts = @($state.OwnedArtifacts)
        } elseif ($state.PSObject.Properties.Name -contains 'ShortcutBackups') {
            $ownedArtifacts = @($state.ShortcutBackups | ForEach-Object { $_.OriginalPath } | Where-Object { $_ })
        }

        [pscustomobject]@{
            Version = if ($state.PSObject.Properties.Name -contains 'Version') { [int]$state.Version } else { 1 }
            Port = $state.Port
            PackageVersion = $state.PackageVersion
            InstallLocation = $state.InstallLocation
            AppExe = $state.AppExe
            RuntimeRoot = if ($state.RuntimeRoot) { $state.RuntimeRoot } else { Get-AiRtlRuntimeRoot }
            LauncherScriptPath = if ($state.LauncherScriptPath) { $state.LauncherScriptPath } else { Get-CodexRtlLauncherScriptPath }
            ShortcutBackups = @($state.ShortcutBackups)
            OwnedArtifacts = @($ownedArtifacts)
            UpdatedAt = $state.UpdatedAt
        }
    } catch {
        Write-Warn "Codex RTL state is unreadable and will be replaced: $($_.Exception.Message)"
        return $null
    }
}

function Save-CodexRtlState {
    param([Parameter(Mandatory)]$State)

    $root = Get-CodexRtlStateRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-CodexRtlStatePath) -Encoding UTF8
}

function New-CodexRtlState {
    param(
        [Parameter(Mandatory)]$Inspection,
        [int]$Port = (Get-CodexRtlDefaultPort),
        [object[]]$ShortcutBackups = @(),
        [string[]]$OwnedArtifacts = @()
    )

    $allOwnedArtifacts = @(
        @($ShortcutBackups | ForEach-Object { $_.OriginalPath })
        $OwnedArtifacts
    ) | Where-Object { $_ } | Select-Object -Unique

    [pscustomobject]@{
        Version = 1
        Port = $Port
        PackageVersion = $Inspection.PackageVersion
        InstallLocation = $Inspection.InstallLocation
        AppExe = $Inspection.AppExe
        RuntimeRoot = Get-AiRtlRuntimeRoot
        LauncherScriptPath = Get-CodexRtlLauncherScriptPath
        ShortcutBackups = @($ShortcutBackups)
        OwnedArtifacts = @($allOwnedArtifacts)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    }
}

function Test-CodexProcessHasRtlDebugPort {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][int]$Port
    )

    return [bool]($Process.CommandLine -match [regex]::Escape("--remote-debugging-port=$Port") -and
        $Process.CommandLine -match [regex]::Escape('--remote-debugging-address=127.0.0.1'))
}

function Get-CodexDesktopProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'Codex.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*' }
}

function Stop-CodexDesktopProcesses {
    foreach ($process in @(Get-CodexDesktopProcesses)) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "Could not stop Codex process $($process.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Start-CodexWithRtlDebug {
    param(
        [Parameter(Mandatory)][string]$AppExe,
        [Parameter(Mandatory)][int]$Port
    )

    Start-Process `
        -FilePath $AppExe `
        -ArgumentList (New-CodexRtlLaunchArguments -Port $Port) `
        -WorkingDirectory (Get-CodexRtlWorkingDirectory) | Out-Null
}

function Start-CodexNormally {
    param([Parameter(Mandatory)][string]$AppExe)

    Start-Process `
        -FilePath $AppExe `
        -ArgumentList @() `
        -WorkingDirectory (Split-Path -Parent $AppExe) | Out-Null
}

function Start-CodexForRtl {
    param(
        [Parameter(Mandatory)]$Inspection,
        [Parameter(Mandatory)][int]$Port,
        [switch]$AllowRestart
    )

    $processes = @(Get-CodexDesktopProcesses)
    if ($processes.Count -eq 0) {
        Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
        return 'started'
    }

    if (@($processes | Where-Object { Test-CodexProcessHasRtlDebugPort -Process $_ -Port $Port }).Count -gt 0) {
        return 'already-running'
    }

    if ($AllowRestart) {
        Write-Host 'Restarting Codex with local RTL injection support...' -ForegroundColor Yellow
        Stop-CodexDesktopProcesses
        Start-Sleep -Milliseconds 700
        Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
        return 'restarted'
    }

    return 'running-without-debug-port'
}

function Test-CodexDevToolsTarget {
    param([Parameter(Mandatory)]$Target)

    if ($Target.type -ne 'page') { return $false }
    if (-not $Target.webSocketDebuggerUrl) { return $false }

    $url = [string]$Target.url
    return ($url -like 'app://*')
}

function Get-CodexDevToolsTargets {
    param([Parameter(Mandatory)][int]$Port)

    $uri = "http://127.0.0.1:$Port/json/list"
    try {
        return @(Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 2)
    } catch {
        return @()
    }
}

function Wait-CodexDevToolsTargets {
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $targets = @(Get-CodexDevToolsTargets -Port $Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
        if ($targets.Count -gt 0) { return $targets }
        Start-Sleep -Milliseconds 500
    }
    return @()
}

function New-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{}
    )

    [pscustomobject]@{
        id = $Id
        method = $Method
        params = [pscustomobject]$Params
    }
}

function Invoke-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][string]$WebSocketDebuggerUrl,
        [Parameter(Mandatory)]$Command
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $buffer = New-Object byte[] 65536
    try {
        $client.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $json = $Command | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $segment = [ArraySegment[byte]]::new($bytes)
        $client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $receive = [ArraySegment[byte]]::new($buffer)
        $message = [System.Collections.Generic.List[byte]]::new()
        $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw 'Codex DevTools closed the WebSocket before returning a response.'
        }
        if ($result.Count -gt 0) {
            $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
        }
        while (-not $result.EndOfMessage) {
            $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'Codex DevTools closed the WebSocket before returning a complete response.'
            }
            if ($result.Count -gt 0) {
                $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
            }
        }
        return [System.Text.Encoding]::UTF8.GetString($message.ToArray())
    } finally {
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        }
        $client.Dispose()
    }
}

function Invoke-CodexRtlInjectionForTarget {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$Payload
    )

    $commands = @(
        (New-CodexCdpCommand -Id 1 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{
            source = $Payload
            runImmediately = $true
        }),
        (New-CodexCdpCommand -Id 2 -Method 'Runtime.evaluate' -Params @{
            expression = $Payload
            awaitPromise = $true
            returnByValue = $true
        })
    )

    foreach ($command in $commands) {
        Invoke-CodexCdpCommand -WebSocketDebuggerUrl $Target.webSocketDebuggerUrl -Command $command | Out-Null
    }
}

function Invoke-CodexRtlInjection {
    param([Parameter(Mandatory)][int]$Port)

    $payload = Get-CodexRtlPayload
    $targets = @(Wait-CodexDevToolsTargets -Port $Port)
    if ($targets.Count -eq 0) {
        Write-Warn "Codex DevTools target was not found on port $Port."
        return $false
    }

    foreach ($target in $targets) {
        try {
            Invoke-CodexRtlInjectionForTarget -Target $target -Payload $payload
        } catch {
            Write-Warn "Codex RTL injection failed for target '$($target.title)': $($_.Exception.Message)"
        }
    }
    return $true
}

function Remove-CodexRtlLegacyWatcherTask {
    $taskName = 'AI RTL Fix Codex RTL Watcher'
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Install-CodexRtlPatch {
    $inspection = Get-CodexInstallInspection
    if (-not $inspection.PackageFound -or -not $inspection.AppExe -or -not (Test-Path -LiteralPath $inspection.AppExe)) {
        throw 'Codex Desktop was not found.'
    }

    $sourceRoot = if ($PSScriptRoot) { Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) } else { Split-Path -Parent (Get-CodexRtlPatchScriptPath) }
    $runtimeRoot = Install-AiRtlRuntimeFiles -SourceRoot $sourceRoot
    $runtimePatchScript = Join-Path $runtimeRoot 'patch.ps1'

    $existingState = Read-CodexRtlState
    $port = if ($existingState -and $existingState.Port) { [int]$existingState.Port } else { Get-CodexRtlAvailablePort }
    Remove-CodexRtlLegacyWatcherTask
    Install-CodexRtlLauncherScript -PatchScriptPath $runtimePatchScript | Out-Null
    Remove-CodexRtlOwnedShortcut -ShortcutPath (Get-CodexRtlShortcutPath) | Out-Null
    Remove-CodexRtlOwnedShortcut -ShortcutPath (Get-CodexRtlLegacyShortcutPath) | Out-Null
    $shortcutSpec = New-CodexLauncherShortcutSpec -Inspection $inspection

    $ownedArtifacts = @()
    $shortcutInventory = @(Get-CodexShortcutInventory)
    $seedableShortcuts = @($shortcutInventory | Where-Object {
        Test-CodexShortcutSeedable -Shortcut $_
    })
    $skippedCodexShortcuts = @($shortcutInventory | Where-Object {
        (Test-CodexShortcutCandidate -Shortcut $_) -and -not (Test-CodexShortcutSeedable -Shortcut $_)
    })
    $createdOrRefreshedCount = 0
    foreach ($shortcut in $seedableShortcuts) {
        try {
            if (Install-CodexParallelRtlShortcutIfPossible -SourceShortcut $shortcut -Spec $shortcutSpec) {
                $ownedArtifacts += Get-CodexSiblingRtlShortcutPath -ShortcutPath $shortcut.Path
                $createdOrRefreshedCount++
            } else {
                $skippedCodexShortcuts += $shortcut
            }
        } catch {
            $skippedCodexShortcuts += $shortcut
            Write-Warn "Codex RTL shortcut creation skipped for $($shortcut.Path): $($_.Exception.Message)"
        }
    }

    try {
        if (Install-CodexStartMenuRtlShortcut -Spec $shortcutSpec) {
            $ownedArtifacts += Get-CodexRtlShortcutPath
            $createdOrRefreshedCount++
        }
    } catch {
        Write-Warn "Codex RTL Start Menu shortcut creation skipped for $(Get-CodexRtlShortcutPath): $($_.Exception.Message)"
    }

    $legacyBackups = if ($existingState -and $existingState.ShortcutBackups) { @($existingState.ShortcutBackups) } else { @() }
    $state = New-CodexRtlState `
        -Inspection $inspection `
        -Port $port `
        -ShortcutBackups $legacyBackups `
        -OwnedArtifacts $ownedArtifacts
    Save-CodexRtlState -State $state

    Start-CodexForRtl -Inspection $inspection -Port $port -AllowRestart | Out-Null
    Invoke-CodexRtlInjection -Port $port | Out-Null

    Write-Host "Codex RTL launcher installed. Created or refreshed $createdOrRefreshedCount Codex RTL shortcut(s), skipped $($skippedCodexShortcuts.Count) candidate location(s). Use Codex RTL shortcuts to launch Codex with RTL support." -ForegroundColor Green
}

function Restore-CodexRtlPatch {
    Remove-CodexRtlLegacyWatcherTask

    $state = Read-CodexRtlState
    $patchedRunningProcess = $null
    $restoreAppExe = $null
    if ($state -and $state.Port) {
        $patchedRunningProcess = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessHasRtlDebugPort -Process $_ -Port ([int]$state.Port)
            }
        ) | Select-Object -First 1
    }
    if ($patchedRunningProcess) {
        if ($state -and $state.AppExe -and (Test-Path -LiteralPath $state.AppExe)) {
            $restoreAppExe = $state.AppExe
        } else {
            $inspection = Get-CodexInstallInspection
            if ($inspection.PackageFound -and $inspection.AppExe -and (Test-Path -LiteralPath $inspection.AppExe)) {
                $restoreAppExe = $inspection.AppExe
            }
        }
        Stop-CodexDesktopProcesses
    }

    $restored = @()
    if ($state -and $state.ShortcutBackups) {
        $restored = @(Restore-CodexShortcutBackups -Backups @($state.ShortcutBackups))
    }

    $ownedArtifacts = if ($state -and $state.OwnedArtifacts) { @($state.OwnedArtifacts) } else { @() }
    if ($ownedArtifacts.Count -eq 0) {
        $ownedArtifacts = @(
            (Get-CodexRtlShortcutPath),
            (Get-CodexRtlLegacyShortcutPath)
        )
    }
    $removedOwnedShortcutCount = 0
    foreach ($ownedArtifact in $ownedArtifacts) {
        $existedBeforeRemoval = Test-Path -LiteralPath $ownedArtifact
        Remove-CodexRtlOwnedShortcut -ShortcutPath $ownedArtifact | Out-Null
        if ($existedBeforeRemoval -and (-not (Test-Path -LiteralPath $ownedArtifact))) {
            $removedOwnedShortcutCount += 1
        }
    }

    $launcherScriptPath = if ($state -and $state.LauncherScriptPath) { $state.LauncherScriptPath } else { Get-CodexRtlLauncherScriptPath }
    if ($launcherScriptPath -and (Test-Path -LiteralPath $launcherScriptPath)) {
        Remove-Item -LiteralPath $launcherScriptPath -Force
    }

    $statePath = Get-CodexRtlStatePath
    if (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force
    }

    if ($patchedRunningProcess -and $restoreAppExe) {
        Start-CodexNormally -AppExe $restoreAppExe
        Write-Host "Codex RTL runtime patch removed. Restored $($restored.Count) legacy shortcut backup(s), removed $removedOwnedShortcutCount owned Codex RTL shortcut(s), and restarted Codex in normal mode." -ForegroundColor Yellow
    } else {
        Write-Host "Codex RTL runtime patch removed. Restored $($restored.Count) legacy shortcut backup(s) and removed $removedOwnedShortcutCount owned Codex RTL shortcut(s). Restart Codex normally if it is still open to clear the already-injected runtime state." -ForegroundColor Yellow
    }
}

function Launch-CodexRtl {
    $inspection = Get-CodexInstallInspection
    if (-not $inspection.PackageFound -or -not $inspection.AppExe -or -not (Test-Path -LiteralPath $inspection.AppExe)) {
        throw 'Codex Desktop was not found.'
    }

    $state = Read-CodexRtlState
    $port = if ($state -and $state.Port) { [int]$state.Port } else { Get-CodexRtlDefaultPort }
    Start-CodexForRtl -Inspection $inspection -Port $port -AllowRestart
    Invoke-CodexRtlInjection -Port $port | Out-Null
}
