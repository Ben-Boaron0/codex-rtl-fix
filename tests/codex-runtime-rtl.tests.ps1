$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

$script:Output = @()

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        [ConsoleColor]$ForegroundColor
    )
    if ($null -ne $Object) {
        $script:Output += (($Object | ForEach-Object { "$_" }) -join ' ')
    }
}

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
Assert-True ($statePath.EndsWith('Codex RTL Fix\state.json')) 'State path should be under the per-user Codex RTL Fix folder.'
Assert-True ((Get-CodexRtlRuntimeRoot).EndsWith('Codex RTL Fix\runtime')) 'Runtime root should be under LocalAppData.'
Assert-True (-not [bool](Get-Command -Name Get-CodexRtlWatcherTaskName -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose watcher task helpers.'
Assert-True (-not [bool](Get-Command -Name Start-CodexRtlWatcher -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose a background watcher.'

$tmpRuntimeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-runtime-copy-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRuntimeRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRuntimeRoot 'LocalAppData'
    $runtimeRoot = Install-CodexRtlRuntimeFiles -SourceRoot $repoRoot
    $requiredRuntimeFiles = @(
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
    foreach ($requiredRuntimeFile in $requiredRuntimeFiles) {
        Assert-True (Test-Path -LiteralPath (Join-Path $runtimeRoot $requiredRuntimeFile)) "Runtime copy should include '$requiredRuntimeFile'."
    }
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRuntimeRoot) {
        Remove-Item -LiteralPath $tmpRuntimeRoot -Recurse -Force
    }
}

$state = New-CodexRtlState -InstallInfo ([pscustomobject]@{
    PackageVersion = '1.2.3'
    InstallLocation = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake'
    AppExe = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
}) -Port 18317 -ShortcutBackups @(
    [pscustomobject]@{
        OriginalPath = 'C:\Users\Test\Desktop\Codex.lnk'
        BackupPath = 'C:\Users\Test\AppData\Local\Codex RTL Fix\backups\shortcuts\abc.lnk'
    }
)
Assert-Equal 1 $state.Version 'Codex RTL state should have an explicit manifest version.'
Assert-True ($state.RuntimeRoot.EndsWith('Codex RTL Fix\runtime')) 'Codex RTL state should persist the runtime root.'
Assert-True ($state.LauncherScriptPath.EndsWith('Codex RTL Fix\runtime\launch-codex-rtl.vbs')) 'Codex RTL state should persist the launcher script path.'
Assert-Equal 1 @($state.OwnedArtifacts).Count 'Codex RTL state should track owned artifacts explicitly.'
Assert-Equal 'C:\Users\Test\Desktop\Codex.lnk' $state.OwnedArtifacts[0] 'Owned artifacts should include tracked shortcut paths.'

$launcherScript = New-CodexRtlLauncherScriptContent -PatchScriptPath (Join-Path (Get-CodexRtlRuntimeRoot) 'patch.ps1')
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
    $fakeInstallInfoForIcon = [pscustomobject]@{
        InstallLocation = $tmpIconRoot
        AppExe = Join-Path $tmpIconRoot 'app\Codex.exe'
    }
    Assert-Equal $fakeIcon (Get-CodexIconLocation -InstallInfo $fakeInstallInfoForIcon) 'Icon location should prefer app\resources\icon.ico.'
} finally {
    if (Test-Path -LiteralPath $tmpIconRoot) { Remove-Item -LiteralPath $tmpIconRoot -Recurse -Force }
}
$fakeInstallInfoFallback = [pscustomobject]@{
    InstallLocation = 'C:\Missing\OpenAI.Codex'
    AppExe = 'C:\Missing\OpenAI.Codex\app\Codex.exe'
}
Assert-Equal "$($fakeInstallInfoFallback.AppExe),0" (Get-CodexIconLocation -InstallInfo $fakeInstallInfoFallback) 'Icon location should fall back to Codex.exe,0 before shell icons.'
$installBody = (Get-Command -Name Install-CodexRtlPatch -CommandType Function).ScriptBlock.ToString()
Assert-True ($installBody.Contains('OwnedArtifacts')) 'Patch flow should persist owned artifacts explicitly.'
Assert-True ($installBody.Contains('Codex RTL')) 'Patch flow should create sibling Codex RTL shortcuts.'
$launchBody = (Get-Command -Name Launch-CodexRtl -CommandType Function).ScriptBlock.ToString()
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
Assert-True (Test-CodexShortcutCandidate -Shortcut $fakeCodexShortcut) 'Writable Codex lnk shortcuts should be recognized as Codex shortcut candidates.'
Assert-True (-not (Test-CodexShortcutCandidate -Shortcut $ambiguousShortcut)) 'Ambiguous non-Codex shortcuts should not be recognized as Codex shortcut candidates.'
Assert-True (Test-CodexShortcutSeedable -Shortcut $fakeCodexShortcut) 'Writable Codex lnk shortcuts should seed sibling Codex RTL shortcuts.'
Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $ambiguousShortcut)) 'Ambiguous non-Codex shortcuts should not seed sibling Codex RTL shortcuts.'
Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $missingShortcut)) 'Missing shortcuts should not seed sibling Codex RTL shortcuts.'
Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $codexFolderOnlyShortcut)) 'A parent folder named Codex should not make an unrelated shortcut seedable.'
Assert-Equal 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Codex RTL.lnk' (Get-CodexSiblingRtlShortcutPath -ShortcutPath $fakeCodexShortcut.Path) 'Sibling Codex RTL path should be derived next to the source shortcut.'
Assert-Equal 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OpenAI\Codex RTL.lnk' (Get-CodexSiblingRtlShortcutPath -ShortcutPath 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OpenAI\Codex.lnk') 'Sibling Codex RTL path should stay inside nested Start Menu folders.'
Assert-Equal (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex RTL.lnk') (Get-CodexRtlShortcutPath) 'Canonical user Start Menu Codex RTL path should target the user Programs folder.'

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-shortcut-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRoot 'LocalAppData'
    $sourceShortcutPath = Join-Path $tmpRoot 'Codex.lnk'
    Set-Content -LiteralPath $sourceShortcutPath -Value 'original shortcut bytes' -Encoding ASCII
    $realShortcut = [pscustomobject]@{
        Path = $sourceShortcutPath
        Name = 'Codex.lnk'
        Exists = $true
        IsLink = $true
        IsWritable = $true
        TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        Arguments = ''
    }
    $rtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $sourceShortcutPath
    $realSpec = New-CodexLauncherShortcutSpec -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRoot
        AppExe = Join-Path $tmpRoot 'Codex.exe'
    })
    New-CodexParallelRtlShortcut -SourceShortcut $realShortcut -Spec $realSpec | Out-Null
    Assert-True (Test-Path -LiteralPath $rtlShortcutPath) 'Parallel Codex RTL shortcut should be created next to the source shortcut.'
    Assert-Equal 'original shortcut bytes' (Get-Content -LiteralPath $sourceShortcutPath -Raw).Trim() 'Creating a parallel Codex RTL shortcut should not modify the original Codex shortcut.'
    Assert-True (Test-CodexRtlOwnedShortcut -ShortcutPath $rtlShortcutPath) 'Created sibling Codex RTL shortcut should be Codex RTL Fix-owned.'

    New-CodexParallelRtlShortcut -SourceShortcut $realShortcut -Spec $realSpec | Out-Null
    Assert-True (Test-Path -LiteralPath $rtlShortcutPath) 'Re-running patch should refresh an existing owned Codex RTL shortcut in place.'

    $foreignRoot = Join-Path $tmpRoot 'foreign'
    New-Item -ItemType Directory -Force -Path $foreignRoot | Out-Null
    $foreignSourceShortcutPath = Join-Path $foreignRoot 'Codex.lnk'
    Set-Content -LiteralPath $foreignSourceShortcutPath -Value 'foreign shortcut bytes' -Encoding ASCII
    $foreignRtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $foreignSourceShortcutPath
    Set-Content -LiteralPath $foreignRtlShortcutPath -Value 'not-owned' -Encoding ASCII
    $foreignShortcut = [pscustomobject]@{
        Path = $foreignSourceShortcutPath
        Name = 'Codex.lnk'
        Exists = $true
        IsLink = $true
        IsWritable = $true
        TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        Arguments = ''
    }
    Assert-True (-not (Install-CodexParallelRtlShortcutIfPossible -SourceShortcut $foreignShortcut -Spec $realSpec)) 'Patch should not overwrite a non-owned sibling Codex RTL shortcut.'
    Assert-Equal 'not-owned' (Get-Content -LiteralPath $foreignRtlShortcutPath -Raw).Trim() 'Patch should leave a non-owned sibling Codex RTL shortcut untouched.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

$tmpInstallRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-install-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpInstallRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
$oldAppData = $env:APPDATA
$oldProgramData = $env:ProgramData
$oldUserProfile = $env:USERPROFILE
$oldPublic = $env:PUBLIC
try {
    $env:LOCALAPPDATA = Join-Path $tmpInstallRoot 'LocalAppData'
    $env:APPDATA = Join-Path $tmpInstallRoot 'AppData\Roaming'
    $env:ProgramData = Join-Path $tmpInstallRoot 'ProgramData'
    $env:USERPROFILE = Join-Path $tmpInstallRoot 'UserProfile'
    $env:PUBLIC = Join-Path $tmpInstallRoot 'Public'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @()

    $fakeInstallRoot = Join-Path $tmpInstallRoot 'WindowsApps\OpenAI.Codex_fake'
    $fakeAppExe = Join-Path $fakeInstallRoot 'app\Codex.exe'
    $fakeIcon = Join-Path $fakeInstallRoot 'app\resources\icon.ico'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeAppExe) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeIcon) | Out-Null
    Set-Content -LiteralPath $fakeAppExe -Value 'exe' -Encoding ASCII
    Set-Content -LiteralPath $fakeIcon -Value 'ico' -Encoding ASCII

    New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') | Out-Null

    function Get-CodexInstallInfo {
        [pscustomobject]@{
            PackageFound = $true
            PackageVersion = '1.2.3'
            InstallLocation = $fakeInstallRoot
            AppExe = $fakeAppExe
        }
    }
    function Install-CodexRtlRuntimeFiles { param([string]$SourceRoot) return (Get-CodexRtlRuntimeRoot) }
    function Get-CodexShortcutInventory { @() }
    function Read-CodexRtlState { $null }
    function Save-CodexRtlState { param($State) $script:SavedState = $State }
    function Start-CodexForRtl {
        param($Inspection, [int]$Port, [switch]$AllowRestart)
        $script:StartedProcesses += 'rtl'
        'started'
    }
    function Invoke-CodexRtlInjection { param([int]$Port) $true }

    Install-CodexRtlPatch

    $fallbackStartMenuShortcut = Get-CodexRtlShortcutPath
    Assert-True (Test-Path -LiteralPath $fallbackStartMenuShortcut) 'Patch should always create a user Start Menu Codex RTL shortcut even when no seedable Codex shortcut exists there.'
    Assert-True (Test-CodexRtlOwnedShortcut -ShortcutPath $fallbackStartMenuShortcut) 'Fallback user Start Menu Codex RTL shortcut should be Codex RTL Fix-owned.'
    Assert-True (@($script:SavedState.OwnedArtifacts) -contains $fallbackStartMenuShortcut) 'Saved state should track the fallback user Start Menu Codex RTL shortcut.'
    Assert-True (($script:Output -join "`n") -match 'Codex RTL launcher installed\.') 'Patch wording should start with a clear success summary.'
    Assert-True (($script:Output -join "`n") -match 'Created or refreshed 1 Codex RTL shortcut') 'Patch wording should count the fallback Start Menu Codex RTL shortcut creation.'
    Assert-True (($script:Output -join "`n") -match 'Skipped 0 candidate location') 'Patch wording should report skipped shortcut locations clearly.'
    Assert-True (($script:Output -join "`n") -match 'Launch Codex using a Codex RTL shortcut') 'Patch wording should tell the user how to start the patched app.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:APPDATA = $oldAppData
    $env:ProgramData = $oldProgramData
    $env:USERPROFILE = $oldUserProfile
    $env:PUBLIC = $oldPublic
    if (Test-Path -LiteralPath $tmpInstallRoot) {
        Remove-Item -LiteralPath $tmpInstallRoot -Recurse -Force
    }
}

. $patchScript -SkipMain

$tmpRestoreRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-restore-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRestoreRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRestoreRoot 'LocalAppData'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 321
            ExecutablePath = Join-Path $tmpRestoreRoot 'Codex.exe'
            CommandLine = '"C:\Fake\Codex.exe" --remote-debugging-port=18317 --remote-debugging-address=127.0.0.1'
        }
    )

    $launcherScriptPath = Get-CodexRtlLauncherScriptPath
    $launcherScriptDir = Split-Path -Parent $launcherScriptPath
    New-Item -ItemType Directory -Force -Path $launcherScriptDir | Out-Null
    Set-Content -LiteralPath $launcherScriptPath -Value 'launcher' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmpRestoreRoot 'Codex.exe') -Value 'exe' -Encoding ASCII

    $originalShortcutPath = Join-Path $tmpRestoreRoot 'Desktop\Codex.lnk'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $originalShortcutPath) | Out-Null
    Set-Content -LiteralPath $originalShortcutPath -Value 'original codex shortcut bytes' -Encoding ASCII

    $ownedShortcutPath = Join-Path $tmpRestoreRoot 'Desktop\Codex RTL.lnk'
    $ownedShortcutDir = Split-Path -Parent $ownedShortcutPath
    New-Item -ItemType Directory -Force -Path $ownedShortcutDir | Out-Null
    $ownedShortcutSpec = New-CodexLauncherShortcutSpec -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRestoreRoot
        AppExe = Join-Path $tmpRestoreRoot 'Codex.exe'
    })
    New-CodexLauncherShortcut -ShortcutPath $ownedShortcutPath -Spec $ownedShortcutSpec

    function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
    function Stop-CodexDesktopProcesses { $script:MockCodexProcesses = @() }
    function Start-Process {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [string]$WorkingDirectory
        )
        $script:StartedProcesses += [pscustomobject]@{
            FilePath = $FilePath
            ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
            HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
            WorkingDirectory = $WorkingDirectory
        }
    }

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
        RuntimeRoot = Get-CodexRtlRuntimeRoot
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

    Assert-Equal 'original codex shortcut bytes' (Get-Content -LiteralPath $originalShortcutPath -Raw).Trim() 'Restore patch should leave the original Codex shortcut untouched.'
    Assert-Equal 'original good shortcut bytes' (Get-Content -LiteralPath $goodOriginalPath -Raw).Trim() 'Restore patch should restore backups that can be copied successfully.'
    Assert-True (-not (Test-Path -LiteralPath $ownedShortcutPath)) 'Restore patch should still remove owned shortcuts after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath $launcherScriptPath)) 'Restore patch should still remove the launcher script after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath (Get-CodexRtlStatePath))) 'Restore patch should still remove the state file after one backup restore fails.'
    Assert-Equal 1 @($script:StartedProcesses).Count 'Restore should restart Codex normally when the patched RTL session is currently running.'
    Assert-Equal (Join-Path $tmpRestoreRoot 'Codex.exe') $script:StartedProcesses[0].FilePath 'Restore restart should use the normal Codex executable path.'
    Assert-True (-not $script:StartedProcesses[0].HasArgumentList) 'Restore restart should omit normal-launch ArgumentList entirely.'
    Assert-Equal 0 @($script:StartedProcesses[0].ArgumentList).Count 'Restore restart should not reuse RTL debug arguments.'
    Assert-True (($script:Output -join "`n") -match 'Codex RTL runtime removed\.') 'Restore wording should start with a clear success summary.'
    Assert-True (($script:Output -join "`n") -match 'Restored 1 shortcut backup') 'Restore wording should clearly count restored shortcut backups.'
    Assert-True (($script:Output -join "`n") -match 'Removed 1 owned Codex RTL shortcut') 'Restore wording should clearly count removed owned shortcuts.'
    Assert-True (($script:Output -join "`n") -match 'Restarted Codex in normal mode\.') 'Restore wording should mention the automatic normal restart on its own line.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRestoreRoot) {
        Remove-Item -LiteralPath $tmpRestoreRoot -Recurse -Force
    }
}

$tmpRestoreNoRestartRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-restore-no-restart-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRestoreNoRestartRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRestoreNoRestartRoot 'LocalAppData'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 654
            ExecutablePath = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
            CommandLine = '"C:\Fake\Codex.exe"'
        }
    )

    $launcherScriptPath = Get-CodexRtlLauncherScriptPath
    $launcherScriptDir = Split-Path -Parent $launcherScriptPath
    New-Item -ItemType Directory -Force -Path $launcherScriptDir | Out-Null
    Set-Content -LiteralPath $launcherScriptPath -Value 'launcher' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmpRestoreNoRestartRoot 'Codex.exe') -Value 'exe' -Encoding ASCII

    $ownedShortcutPath = Join-Path $tmpRestoreNoRestartRoot 'Desktop\Codex RTL.lnk'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ownedShortcutPath) | Out-Null
    $ownedShortcutSpec = New-CodexLauncherShortcutSpec -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRestoreNoRestartRoot
        AppExe = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
    })
    New-CodexLauncherShortcut -ShortcutPath $ownedShortcutPath -Spec $ownedShortcutSpec

    function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
    function Stop-CodexDesktopProcesses { $script:MockCodexProcesses = @() }
    function Start-Process {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [string]$WorkingDirectory
        )
        $script:StartedProcesses += [pscustomobject]@{
            FilePath = $FilePath
            ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
            HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
            WorkingDirectory = $WorkingDirectory
        }
    }

    Save-CodexRtlState -State ([pscustomobject]@{
        Version = 1
        Port = 18317
        PackageVersion = '1.2.3'
        InstallLocation = $tmpRestoreNoRestartRoot
        AppExe = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
        RuntimeRoot = Get-CodexRtlRuntimeRoot
        LauncherScriptPath = $launcherScriptPath
        ShortcutBackups = @()
        OwnedArtifacts = @($ownedShortcutPath)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    })

    Restore-CodexRtlPatch

    Assert-Equal 0 @($script:StartedProcesses).Count 'Restore should not restart Codex when the current session is not the RTL-patched one.'
    Assert-True (($script:Output -join "`n") -match 'Codex RTL runtime removed\.') 'Restore wording should still start with a clear success summary when no restart happens.'
    Assert-True (($script:Output -join "`n") -match 'Restored 0 shortcut backup') 'Restore wording should report zero restored backups when none existed.'
    Assert-True (($script:Output -join "`n") -match 'Removed 1 owned Codex RTL shortcut') 'Restore wording should still report removed owned shortcuts when no restart happens.'
    Assert-True (($script:Output -join "`n") -match 'Restart Codex normally if it is still open\.') 'Restore wording should explain the manual normal restart when no patched RTL session was restarted automatically.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRestoreNoRestartRoot) {
        Remove-Item -LiteralPath $tmpRestoreNoRestartRoot -Recurse -Force
    }
}

$args = New-CodexRtlLaunchArguments -Port 18317
Assert-True ($args -contains '--remote-debugging-port=18317') 'Launch args should enable CDP on the chosen port.'
Assert-True ($args -contains '--remote-debugging-address=127.0.0.1') 'Launch args should bind CDP to loopback only.'

$script:DirectStartProcessCalls = @()
function Start-Process {
    param(
        [string]$FilePath,
        [object[]]$ArgumentList,
        [string]$WorkingDirectory
    )
    if ($PSBoundParameters.ContainsKey('ArgumentList') -and @($ArgumentList).Count -eq 0) {
        throw 'ArgumentList should be omitted when no normal-launch arguments are needed.'
    }
    $script:DirectStartProcessCalls += [pscustomobject]@{
        FilePath = $FilePath
        ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
        HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
        WorkingDirectory = $WorkingDirectory
    }
}
Start-CodexNormally -AppExe 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
Assert-Equal 1 @($script:DirectStartProcessCalls).Count 'Normal launch should invoke Start-Process once.'
Assert-True (-not $script:DirectStartProcessCalls[0].HasArgumentList) 'Normal launch should omit ArgumentList entirely.'
Assert-Equal 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe' $script:DirectStartProcessCalls[0].FilePath 'Normal launch should use the Codex executable path.'
Assert-Equal 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app' $script:DirectStartProcessCalls[0].WorkingDirectory 'Normal launch should use the executable parent directory as the working directory.'

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
Assert-True ($payload.Contains('window.__CODEX_RTL_FIX_CODEX')) 'Payload should be idempotent.'
Assert-True ($payload.Contains('classifyDirection')) 'Payload should classify text direction.'
Assert-True ($payload.Contains('RTL_RE')) 'Payload should detect RTL codepoints.'
Assert-True ($payload.Contains('unicodeBidi')) 'Payload should use bidi-safe rendering.'
Assert-True ($payload.Contains('data-codex-rtl-fix')) 'Payload should mark only tool-owned changes.'
Assert-True ($payload.Contains('removeAttribute(''dir'')') -or $payload.Contains('removeAttribute("dir")')) 'Payload should clean stale broad dir attributes.'
Assert-True (-not ($payload -match "querySelectorAll\('\[data-thread-find-target=.*setAttribute\('dir', 'rtl'")) 'Payload should not force the conversation root to RTL.'
Assert-True (-not ($payload.Contains('numberCount > 0 && rtlCount > 0'))) 'Payload should not classify RTL text as mixed-LTR just because it contains numbers.'
Assert-True ($payload.Contains('function getMeaningfulText')) 'Payload should strip diagnostic prefixes before classifying block direction.'
Assert-True ($payload.Contains('function applyBlockDirection')) 'Payload should apply block direction through one helper.'
Assert-True ($payload.Contains('function processInlineTechnicalIslands')) 'Payload should isolate inline technical fragments explicitly.'
Assert-True ($payload.Contains('function processLists')) 'Payload should process list structure explicitly.'
Assert-True ($payload.Contains('function processBlockquotes')) 'Payload should process blockquote structure explicitly.'
Assert-True (-not ($payload.Contains('processTables(bubble)'))) 'Payload should not patch table cells inside user bubbles.'
Assert-True (-not ($payload.Contains('processTables(root)'))) 'Payload should not patch table cells inside conversation roots.'
Assert-True ($payload.Contains('[data-thread-find-target="conversation"]')) 'Payload should keep the existing conversation-root targeting.'
Assert-True ($payload.Contains('span[data-thread-title="true"]')) 'Payload should target verified sidebar thread title spans.'
Assert-True ($payload.Contains('data-app-action-sidebar-project-row')) 'Payload should target verified sidebar project rows.'
Assert-True ($payload.Contains('data-app-action-sidebar-project-label')) 'Payload should target verified sidebar project labels.'
Assert-True ($payload.Contains('app-shell-header-context-menu-surface')) 'Payload should target the app header title surface.'
Assert-True ($payload.Contains('[data-user-message-bubble="true"]')) 'Payload should target verified user message bubbles directly.'
Assert-True ($payload.Contains('div.ProseMirror')) 'Payload should target ProseMirror composers and edit boxes.'
Assert-True ($payload.Contains('textarea')) 'Payload should target standard textareas for auto direction.'
Assert-True ($payload.Contains('[contenteditable="true"]')) 'Payload should keep quoted contenteditable composer support.'
Assert-True ($payload.Contains('[contenteditable=true]')) 'Payload should keep unquoted contenteditable composer support.'
Assert-True ($payload.Contains('ol, ul')) 'Payload should handle ordered and unordered list containers explicitly.'
Assert-True ($payload.Contains('input[type="checkbox"]')) 'Payload should account for task-list checkbox markers.'
Assert-True ($payload.Contains('data-codex-rtl-fix-style')) 'Payload should inject a dedicated stylesheet for technical inline fragments.'
Assert-True ($payload.Contains('unicode-bidi: isolate')) 'Payload stylesheet should isolate inline technical fragments safely.'
Assert-True (-not ($payload.Contains('unicode-bidi: isolate-override !important'))) 'Payload should avoid isolate-override because it flips Hebrew in mixed technical surfaces.'
Assert-True ($payload.Contains('border-left: 0 !important')) 'RTL blockquote styling should explicitly remove Codex left quote border.'
Assert-True ($payload.Contains('border-right: 0.25rem solid currentColor !important')) 'RTL blockquote styling should explicitly add the quote border on the right.'
Assert-True ($payload.Contains('padding-left: 0 !important')) 'RTL blockquote styling should explicitly clear left padding.'
Assert-True ($payload.Contains('padding-right: 1rem !important')) 'RTL blockquote styling should explicitly add right padding.'
foreach ($tableSelector in @('table', 'thead', 'tbody', 'tr', 'th', 'td')) {
    Assert-True ($payload.Contains("'$tableSelector'") -or $payload.Contains('"$tableSelector"')) "Payload skip selector should shield '$tableSelector' elements."
}
$textSelectorsOnly = ($payload -split 'const SKIP_SELECTOR')[0]
Assert-True (-not $textSelectorsOnly.Contains("'td'")) 'Payload text block targeting should not include table cells.'
Assert-True (-not $textSelectorsOnly.Contains("'th'")) 'Payload text block targeting should not include table headers.'
Assert-True ($payload.Contains('MutationObserver')) 'Payload should reapply after React DOM changes.'

$nodeCommand = Get-Command -Name node -ErrorAction SilentlyContinue
if ($nodeCommand) {
    $payloadTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rtl-payload-{0}.js" -f ([guid]::NewGuid().ToString('N')))
    $runnerTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rtl-runner-{0}.js" -f ([guid]::NewGuid().ToString('N')))
    try {
        Set-Content -LiteralPath $payloadTempPath -Value $payload -Encoding UTF8
        Set-Content -LiteralPath $runnerTempPath -Encoding UTF8 -Value @'
const fs = require('fs');
const vm = require('vm');
const payload = fs.readFileSync(process.argv[2], 'utf8');

const context = {
  console,
  window: { setTimeout: (fn) => fn() },
  document: {
    readyState: 'loading',
    addEventListener: () => {},
    querySelectorAll: () => [],
    head: {
      querySelector: () => null,
      appendChild: () => {}
    },
    createElement: () => ({
      setAttribute: () => {},
      style: {},
      textContent: ''
    })
  },
  MutationObserver: function MutationObserver() {
    return {
      observe: () => {},
      disconnect: () => {}
    };
  }
};

vm.runInNewContext(payload, context);
const classify = context.window.__CODEX_RTL_FIX_CODEX.classifyDirection;
const cases = [
  ['rtl', '\u05e2\u05d1\u05e8\u05d9\u05ea \u05e2\u05dd \u05de\u05e1\u05e4\u05e8 \u05e4\u05e0\u05d9\u05de\u05d9 123 \u05d1\u05d0\u05de\u05e6\u05e2 \u05d4\u05de\u05e9\u05e4\u05d8'],
  ['rtl', 'A03. Hebrew then English: \u05e9\u05dc\u05d5\u05dd LoginActivity update README'],
  ['rtl', '50 \u05d5\u05e8\u05d9\u05d0\u05e6\u05d9\u05d5\u05ea \u05e7\u05e6\u05e8\u05d5\u05ea \u05d1\u05de\u05d9\u05d5\u05d7\u05d3'],
  ['rtl', '\u05db\u05d5\u05ea\u05e8\u05ea \u05e2\u05dd inline code \u05d5-English'],
  ['rtl', 'H05. Compare dir="rtl" \u05de\u05d5\u05dc dir="auto" \u05d1\u05ea\u05d5\u05da \u05de\u05e9\u05e4\u05d8 \u05e2\u05d1\u05e8\u05d9.'],
  ['ltr', 'Please review \u05e9\u05dc\u05d5\u05dd world'],
  ['ltr', 'English only ID-1234']
];

for (const [expected, input] of cases) {
  const actual = classify(input);
  if (actual !== expected) {
    throw new Error(`${input}: expected ${expected}, got ${actual}`);
  }
}
'@
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $nodeOutput = & $nodeCommand.Path $runnerTempPath $payloadTempPath 2>&1 | ForEach-Object { "$_" }
            $nodeExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
        if ($nodeExitCode -ne 0) {
            throw "Payload classifier behavior check failed:`n$($nodeOutput | Out-String)"
        }
    } finally {
        foreach ($tempPath in @($payloadTempPath, $runnerTempPath)) {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
    }
}

$cdpBody = (Get-Command -Name Invoke-CodexRtlInjectionForTarget -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpBody.Contains('Page.addScriptToEvaluateOnNewDocument')) 'Injection should install the payload for future documents.'
Assert-True ($cdpBody.Contains('Runtime.evaluate')) 'Injection should also evaluate the payload in the current document.'

$cdpCommandBody = (Get-Command -Name Invoke-CodexCdpCommand -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpCommandBody.Contains('while (-not $result.EndOfMessage)')) 'CDP command responses should keep reading until EndOfMessage.'
Assert-True ($cdpCommandBody.Contains('WebSocketMessageType]::Close')) 'CDP command responses should reject close frames while reading.'

Write-Host 'codex-runtime-rtl.tests.ps1 passed'
