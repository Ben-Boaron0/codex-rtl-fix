# HELPER FUNCTIONS
# -----------------------------------------------------------------------------
# Persistent log for Codex RTL Fix operations.
$global:PatchLogFile = Join-Path $env:ProgramData "CodexRtlFix\patch.log"

function Write-LogToFile($level, $msg) {
    try {
        $dir = Split-Path -Parent $global:PatchLogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Rotate at 1 MB to keep the file readable. One generation of history is enough.
        if ((Test-Path $global:PatchLogFile) -and (Get-Item $global:PatchLogFile).Length -gt 1MB) {
            Move-Item $global:PatchLogFile "$global:PatchLogFile.old" -Force
        }
        "$([DateTime]::Now.ToString('o'))  [$level] $msg" |
            Out-File -Append -FilePath $global:PatchLogFile -Encoding UTF8
    } catch {}
}

function Write-Warn($msg)    { Write-Host "  [!] $msg" -ForegroundColor Yellow;  Write-LogToFile 'WARN' $msg }

# -----------------------------------------------------------------------------
