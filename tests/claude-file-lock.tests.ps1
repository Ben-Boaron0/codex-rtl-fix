$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw $Message }
}

Assert-True ([bool](Get-Command -Name Test-FileLock -CommandType Function -ErrorAction SilentlyContinue)) 'Test-FileLock should load.'
Assert-True ([bool](Get-Command -Name Wait-FileUnlock -CommandType Function -ErrorAction SilentlyContinue)) 'Wait-FileUnlock should load.'

$invalidAccessThrew = $false
try {
    Test-FileLock -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'missing-ai-rtl-file.tmp') -Access Execute | Out-Null
} catch {
    $invalidAccessThrew = ($_.Exception.Message -match 'Unsupported file access probe')
}
Assert-True $invalidAccessThrew 'Test-FileLock should throw for unsupported access values instead of reporting a lock.'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-rtl-lock-test-{0}.bin" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllBytes($tmp, [byte[]](1, 2, 3, 4))

try {
    $holder = [System.IO.File]::Open(
        $tmp,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        Assert-False (Test-FileLock -Path $tmp -Access Write) 'Write probe should allow a benign read handle that shares ReadWrite.'
        Assert-False (Test-FileLock -Path $tmp -Access Read) 'Read probe should allow a benign read handle that shares ReadWrite.'
        Wait-FileUnlock -Path $tmp -TimeoutSeconds 1 -Access Write
        Wait-FileUnlock -Path $tmp -TimeoutSeconds 1 -Access Read
    } finally {
        $holder.Close()
    }

    $readOnlyShareHolder = [System.IO.File]::Open(
        $tmp,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        Assert-True (Test-FileLock -Path $tmp -Access Write) 'Write probe should detect a read-only-share holder that would block WriteAllBytes.'
        Assert-False (Test-FileLock -Path $tmp -Access Read) 'Read probe should allow a read-only-share holder because backup reads can proceed.'
    } finally {
        $readOnlyShareHolder.Close()
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'claude-file-lock.tests.ps1 passed'
