function Get-CodexRtlShortcutPath {
    Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex RTL.lnk'
}

function Get-CodexShortcutBackupRoot {
    Join-Path (Get-CodexRtlStateRoot) 'backups\shortcuts'
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
    param($InstallInfo)

    if ($InstallInfo -and $InstallInfo.InstallLocation) {
        $icon = Join-Path $InstallInfo.InstallLocation 'app\resources\icon.ico'
        if (Test-Path -LiteralPath $icon) { return $icon }
    }
    if ($InstallInfo -and $InstallInfo.AppExe) {
        return "$($InstallInfo.AppExe),0"
    }
    return "$env:SystemRoot\System32\shell32.dll,167"
}

function New-CodexLauncherShortcutSpec {
    param($InstallInfo = $null)

    $launcherScript = Get-CodexRtlLauncherScriptPath
    [pscustomobject]@{
        TargetPath = "$env:SystemRoot\System32\wscript.exe"
        Arguments = "`"$launcherScript`""
        WorkingDirectory = Get-CodexRtlWorkingDirectory
        IconLocation = Get-CodexIconLocation -InstallInfo $InstallInfo
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
