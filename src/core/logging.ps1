# HELPER FUNCTIONS
# -----------------------------------------------------------------------------
# Persistent log -- captures every patch run (including silent ones triggered by
# the auto-update watcher) so failures can be diagnosed after the fact.
$global:PatchLogFile = Join-Path $env:ProgramData "ClaudeRtlPatch\patch.log"

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

function Write-Log($msg)     { Write-Host "  [*] $msg" -ForegroundColor Cyan;    Write-LogToFile 'INFO' $msg }
function Write-Step($msg)    { Write-Host "`n► $msg" -ForegroundColor Magenta;   Write-LogToFile 'STEP' $msg }
function Write-Success($msg) { Write-Host "  [+] $msg" -ForegroundColor Green;   Write-LogToFile 'OK'   $msg }
function Write-Warn($msg)    { Write-Host "  [!] $msg" -ForegroundColor Yellow;  Write-LogToFile 'WARN' $msg }

# Pure Binary Search equivalent to Python's bytearray.find()
function Find-Bytes([byte[]]$Haystack, [byte[]]$Needle, [int]$StartIndex = 0) {
    # Fast path: convert both arrays to ISO-8859-1 strings (1 byte ↔ 1 char, lossless
    # for all 256 byte values) and delegate to String.IndexOf, which is implemented in
    # native code. This replaces a nested PowerShell byte-by-byte loop that was the
    # dominant silent period during patching (tens of MB × needle length in pure PS
    # could take ~30–60s on claude.exe).
    if ($Needle -eq $null -or $Needle.Length -eq 0 -or $Haystack -eq $null -or $Haystack.Length -lt $Needle.Length) { return -1 }
    if ($StartIndex -lt 0) { $StartIndex = 0 }
    if ($StartIndex -gt ($Haystack.Length - $Needle.Length)) { return -1 }
    $enc = [System.Text.Encoding]::GetEncoding(28591)  # ISO-8859-1 / Latin-1, byte-preserving
    $hayStr = $enc.GetString($Haystack)
    $needleStr = $enc.GetString($Needle)
    return $hayStr.IndexOf($needleStr, $StartIndex, [System.StringComparison]::Ordinal)
}

# -----------------------------------------------------------------------------
