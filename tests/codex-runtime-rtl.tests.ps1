$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$statePath = Get-CodexRtlStatePath
Assert-True ($statePath.EndsWith('AI RTL Fix\Codex\state.json')) 'State path should be under the per-user AI RTL Fix Codex folder.'
Assert-True ((Get-AiRtlRuntimeRoot).EndsWith('AI RTL Fix\runtime')) 'Runtime root should be under LocalAppData.'
Assert-True (-not [bool](Get-Command -Name Get-CodexRtlWatcherTaskName -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose watcher task helpers.'
Assert-True (-not [bool](Get-Command -Name Start-CodexRtlWatcher -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose a background watcher.'

$state = New-CodexRtlState -Inspection ([pscustomobject]@{
    PackageVersion = '1.2.3'
    InstallLocation = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake'
    AppExe = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
}) -Port 18317 -ShortcutBackups @(
    [pscustomobject]@{
        OriginalPath = 'C:\Users\Test\Desktop\Codex.lnk'
        BackupPath = 'C:\Users\Test\AppData\Local\AI RTL Fix\Codex\backups\shortcuts\abc.lnk'
    }
)
Assert-Equal 1 $state.Version 'Codex RTL state should have an explicit manifest version.'
Assert-True ($state.RuntimeRoot.EndsWith('AI RTL Fix\runtime')) 'Codex RTL state should persist the runtime root.'
Assert-True ($state.LauncherScriptPath.EndsWith('AI RTL Fix\runtime\launch-codex-rtl.vbs')) 'Codex RTL state should persist the launcher script path.'
Assert-Equal 1 @($state.OwnedArtifacts).Count 'Codex RTL state should track owned artifacts explicitly.'
Assert-Equal 'C:\Users\Test\Desktop\Codex.lnk' $state.OwnedArtifacts[0] 'Owned artifacts should include replaced shortcut paths.'
Assert-True (-not [bool](Get-Command -Name Install-CodexRtlShortcut -CommandType Function -ErrorAction SilentlyContinue)) 'Patch should not create a duplicate Start Menu launcher shortcut.'

$launcherScript = New-CodexRtlLauncherScriptContent -PatchScriptPath (Join-Path (Get-AiRtlRuntimeRoot) 'patch.ps1')
Assert-True ($launcherScript.Contains('powershell.exe')) 'VBS launcher should run PowerShell internally.'
Assert-True ($launcherScript.Contains('-LaunchCodexRtl')) 'VBS launcher should call the explicit Codex launch entrypoint.'
Assert-True ($launcherScript.Contains('Chr(34)')) 'VBS launcher should build the quoted patch path using Chr(34).'
Assert-True ($launcherScript -match 'command = "powershell\.exe .* -File " & Chr\(34\) & ".*" & Chr\(34\) & " -LaunchCodexRtl"') 'VBS launcher should concatenate the quoted patch path safely.'
Assert-True ($launcherScript.Contains(', 0, False')) 'VBS launcher should hide the window and not wait.'

$tmpIconRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-icon-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path (Join-Path $tmpIconRoot 'app\resources') | Out-Null
try {
    $fakeIcon = Join-Path $tmpIconRoot 'app\resources\icon.ico'
    Set-Content -LiteralPath $fakeIcon -Value 'ico' -Encoding ASCII
    $fakeInspectionForIcon = [pscustomobject]@{
        InstallLocation = $tmpIconRoot
        AppExe = Join-Path $tmpIconRoot 'app\Codex.exe'
    }
    Assert-Equal $fakeIcon (Get-CodexIconLocation -Inspection $fakeInspectionForIcon) 'Icon location should prefer app\resources\icon.ico.'
} finally {
    if (Test-Path -LiteralPath $tmpIconRoot) { Remove-Item -LiteralPath $tmpIconRoot -Recurse -Force }
}
$fakeInspectionFallback = [pscustomobject]@{
    InstallLocation = 'C:\Missing\OpenAI.Codex'
    AppExe = 'C:\Missing\OpenAI.Codex\app\Codex.exe'
}
Assert-Equal "$($fakeInspectionFallback.AppExe),0" (Get-CodexIconLocation -Inspection $fakeInspectionFallback) 'Icon location should fall back to Codex.exe,0 before shell icons.'
$installBody = (Get-Command -Name Install-CodexRtlPatch -CommandType Function).ScriptBlock.ToString()
Assert-True (-not ($installBody -match 'Install-CodexRtlShortcut')) 'Patch flow should not install a canonical Start Menu shortcut.'
Assert-True ($installBody.Contains('OwnedArtifacts')) 'Patch flow should persist owned artifacts explicitly.'
$launchBody = (Get-Command -Name Launch-CodexRtl -CommandType Function).ScriptBlock.ToString()
Assert-True (-not ($launchBody.Contains('Start-CodexWithRtlActivation'))) 'Codex launch should use the known-working direct executable path.'
Assert-True ($launchBody.Contains('Start-CodexForRtl')) 'Codex launch should delegate to the approved-verb launch helper.'

$roots = @(Get-CodexShortcutSearchRoots)
Assert-True ($roots -contains (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')) 'Shortcut search should include user Start Menu programs.'
Assert-True ($roots -contains (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')) 'Shortcut search should include all-users Start Menu programs.'
Assert-True ($roots -contains (Join-Path $env:USERPROFILE 'Desktop')) 'Shortcut search should include user Desktop.'
Assert-True ($roots -contains (Join-Path $env:PUBLIC 'Desktop')) 'Shortcut search should include public Desktop.'
Assert-True ($roots -contains (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')) 'Shortcut search should include normal taskbar pinned shortcut folder.'

$fakeCodexShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Codex.lnk'
    Name = 'Codex.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__2p2nqsd0c76g0\app\Codex.exe'
    Arguments = ''
}
$ambiguousShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\Desktop\Notes.lnk'
    Name = 'Notes.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Windows\notepad.exe'
    Arguments = ''
}
$missingShortcut = [pscustomobject]@{
    Path = 'C:\Missing\Codex.lnk'
    Name = 'Codex.lnk'
    Exists = $false
    IsLink = $true
    IsWritable = $false
    TargetPath = ''
    Arguments = ''
}
$codexFolderOnlyShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\Documents\Codex\Notes.lnk'
    Name = 'Notes.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Windows\notepad.exe'
    Arguments = ''
}
Assert-True (Test-CodexShortcutReplaceable -Shortcut $fakeCodexShortcut) 'Writable Codex lnk shortcuts should be replaceable.'
Assert-True (-not (Test-CodexShortcutReplaceable -Shortcut $ambiguousShortcut)) 'Ambiguous non-Codex shortcuts should not be replaceable.'
Assert-True (-not (Test-CodexShortcutReplaceable -Shortcut $missingShortcut)) 'Missing shortcuts should not be replaceable.'
Assert-True (-not (Test-CodexShortcutReplaceable -Shortcut $codexFolderOnlyShortcut)) 'A parent folder named Codex should not make an unrelated shortcut replaceable.'

$backupPathBody = (Get-Command -Name Get-StableShortcutBackupPath -CommandType Function).ScriptBlock.ToString()
Assert-True ($backupPathBody.Contains('try {')) 'Stable shortcut backup hashing should wrap SHA256 use in try/finally.'
Assert-True ($backupPathBody.Contains('$sha.Dispose()')) 'Stable shortcut backup hashing should dispose the SHA256 instance.'

$backup = New-CodexShortcutBackupRecord -Shortcut $fakeCodexShortcut -BackupPath 'C:\Backup\abc.lnk' -Kind 'StartMenu'
Assert-Equal $fakeCodexShortcut.Path $backup.OriginalPath 'Backup metadata should record original path.'
Assert-Equal 'C:\Backup\abc.lnk' $backup.BackupPath 'Backup metadata should record backup path.'
Assert-Equal $fakeCodexShortcut.TargetPath $backup.OriginalTargetPath 'Backup metadata should record original target.'

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-shortcut-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRoot 'LocalAppData'
    $shortcutPath = Join-Path $tmpRoot 'Codex.lnk'
    Set-Content -LiteralPath $shortcutPath -Value 'original shortcut bytes' -Encoding ASCII
    $realShortcut = [pscustomobject]@{
        Path = $shortcutPath
        Name = 'Codex.lnk'
        Exists = $true
        IsLink = $true
        IsWritable = $true
        TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        Arguments = ''
    }
    $realBackup = Backup-CodexShortcut -Shortcut $realShortcut
    Set-Content -LiteralPath $shortcutPath -Value 'replacement shortcut bytes' -Encoding ASCII
    $restored = @(Restore-CodexShortcutBackups -Backups @($realBackup))
    Assert-Equal 1 $restored.Count 'Restore should report one restored backup.'
    Assert-Equal 'original shortcut bytes' (Get-Content -LiteralPath $shortcutPath -Raw).Trim() 'Restore should put the original shortcut bytes back.'
    $unrelatedPath = Join-Path $tmpRoot 'Other.lnk'
    Set-Content -LiteralPath $unrelatedPath -Value 'unrelated' -Encoding ASCII
    Restore-CodexShortcutBackups -Backups @($realBackup) | Out-Null
    Assert-Equal 'unrelated' (Get-Content -LiteralPath $unrelatedPath -Raw).Trim() 'Restore should not touch unrelated shortcuts.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

$tmpRestoreRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-restore-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRestoreRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRestoreRoot 'LocalAppData'

    $launcherScriptPath = Get-CodexRtlLauncherScriptPath
    $launcherScriptDir = Split-Path -Parent $launcherScriptPath
    New-Item -ItemType Directory -Force -Path $launcherScriptDir | Out-Null
    Set-Content -LiteralPath $launcherScriptPath -Value 'launcher' -Encoding ASCII

    $ownedShortcutPath = Join-Path $tmpRestoreRoot 'Desktop\Codex RTL Fix.lnk'
    $ownedShortcutDir = Split-Path -Parent $ownedShortcutPath
    New-Item -ItemType Directory -Force -Path $ownedShortcutDir | Out-Null
    $ownedShortcutSpec = New-CodexLauncherShortcutSpec -Inspection ([pscustomobject]@{
        InstallLocation = $tmpRestoreRoot
        AppExe = Join-Path $tmpRestoreRoot 'Codex.exe'
    })
    New-CodexLauncherShortcut -ShortcutPath $ownedShortcutPath -Spec $ownedShortcutSpec

    $backupRoot = Join-Path $tmpRestoreRoot 'backups'
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

    $goodBackupPath = Join-Path $backupRoot 'good.lnk'
    Set-Content -LiteralPath $goodBackupPath -Value 'original good shortcut bytes' -Encoding ASCII
    $goodOriginalPath = Join-Path $tmpRestoreRoot 'Restored\Codex.lnk'

    $badBackupPath = Join-Path $backupRoot 'bad.lnk'
    Set-Content -LiteralPath $badBackupPath -Value 'original bad shortcut bytes' -Encoding ASCII
    $badParentPath = Join-Path $tmpRestoreRoot 'blocked-parent'
    Set-Content -LiteralPath $badParentPath -Value 'not a directory' -Encoding ASCII
    $badOriginalPath = Join-Path $badParentPath 'Codex.lnk'

    $state = [pscustomobject]@{
        Version = 1
        Port = 18317
        PackageVersion = '1.2.3'
        InstallLocation = $tmpRestoreRoot
        AppExe = Join-Path $tmpRestoreRoot 'Codex.exe'
        RuntimeRoot = Get-AiRtlRuntimeRoot
        LauncherScriptPath = $launcherScriptPath
        ShortcutBackups = @(
            [pscustomobject]@{
                OriginalPath = $goodOriginalPath
                BackupPath = $goodBackupPath
            },
            [pscustomobject]@{
                OriginalPath = $badOriginalPath
                BackupPath = $badBackupPath
            }
        )
        OwnedArtifacts = @($ownedShortcutPath)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Save-CodexRtlState -State $state

    Restore-CodexRtlPatch

    Assert-Equal 'original good shortcut bytes' (Get-Content -LiteralPath $goodOriginalPath -Raw).Trim() 'Restore patch should restore backups that can be copied successfully.'
    Assert-True (-not (Test-Path -LiteralPath $ownedShortcutPath)) 'Restore patch should still remove owned shortcuts after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath $launcherScriptPath)) 'Restore patch should still remove the launcher script after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath (Get-CodexRtlStatePath))) 'Restore patch should still remove the state file after one backup restore fails.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRestoreRoot) {
        Remove-Item -LiteralPath $tmpRestoreRoot -Recurse -Force
    }
}

$args = New-CodexRtlLaunchArguments -Port 18317
Assert-True ($args -contains '--remote-debugging-port=18317') 'Launch args should enable CDP on the chosen port.'
Assert-True ($args -contains '--remote-debugging-address=127.0.0.1') 'Launch args should bind CDP to loopback only.'

$pageTarget = [pscustomobject]@{
    type = 'page'
    url = 'app://codex/webview/index.html'
    title = 'Codex'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/1'
}
$devtoolsTarget = [pscustomobject]@{
    type = 'other'
    url = 'devtools://devtools/bundled/inspector.html'
    title = 'DevTools'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/2'
}
$remoteTarget = [pscustomobject]@{
    type = 'page'
    url = 'https://example.com/'
    title = 'Example'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/3'
}
$codexTitledRemoteTarget = [pscustomobject]@{
    type = 'page'
    url = 'https://docs.example.com/'
    title = 'Codex Documentation'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/4'
}
Assert-True (Test-CodexDevToolsTarget -Target $pageTarget) 'Codex app page targets should be accepted.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $devtoolsTarget)) 'Non-page DevTools targets should be rejected.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $remoteTarget)) 'Unrelated web page targets should be rejected.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $codexTitledRemoteTarget)) 'Non-app pages should be rejected even when their title contains Codex.'

$payload = Get-CodexRtlPayload
Assert-True ($payload.Contains('window.__AI_RTL_FIX_CODEX')) 'Payload should be idempotent.'
Assert-True ($payload.Contains('classifyDirection')) 'Payload should classify text direction.'
Assert-True ($payload.Contains('RTL_RE')) 'Payload should detect RTL codepoints.'
Assert-True ($payload.Contains('unicodeBidi')) 'Payload should use bidi-safe rendering.'
Assert-True ($payload.Contains('data-ai-rtl-fix')) 'Payload should mark only tool-owned changes.'
Assert-True ($payload.Contains('removeAttribute(''dir'')') -or $payload.Contains('removeAttribute("dir")')) 'Payload should clean stale broad dir attributes.'
Assert-True (-not ($payload -match "querySelectorAll\('\[data-thread-find-target=.*setAttribute\('dir', 'rtl'")) 'Payload should not force the conversation root to RTL.'
Assert-True ($payload.Contains('[contenteditable="true"]')) 'Payload should target quoted contenteditable composers.'
Assert-True ($payload.Contains('[contenteditable=true]')) 'Payload should target unquoted contenteditable composers.'
Assert-True ($payload.Contains('MutationObserver')) 'Payload should reapply after React DOM changes.'

$cdpBody = (Get-Command -Name Invoke-CodexRtlInjectionForTarget -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpBody.Contains('Page.addScriptToEvaluateOnNewDocument')) 'Injection should install the payload for future documents.'
Assert-True ($cdpBody.Contains('Runtime.evaluate')) 'Injection should also evaluate the payload in the current document.'

$cdpCommandBody = (Get-Command -Name Invoke-CodexCdpCommand -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpCommandBody.Contains('while (-not $result.EndOfMessage)')) 'CDP command responses should keep reading until EndOfMessage.'
Assert-True ($cdpCommandBody.Contains('WebSocketMessageType]::Close')) 'CDP command responses should reject close frames while reading.'

Write-Host 'codex-runtime-rtl.tests.ps1 passed'
