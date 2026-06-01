# AUTO-UPDATE STATE: shared with the watcher Scheduled Task
# -----------------------------------------------------------------------------
$global:RtlStateDir  = Join-Path $env:ProgramData "ClaudeRtlPatch"
$global:RtlStateFile = Join-Path $global:RtlStateDir "state.json"
$global:RtlTaskName  = "ClaudeRtlPatchWatcher"

function Get-ClaudeVersionFromPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $leaf = Split-Path -Leaf $Path
    if ($leaf -match '^Claude_(\d+(?:\.\d+){1,3})_') {
        try { return [Version]$matches[1] } catch { return $null }
    }
    # Path may also be the inner app dir; walk up one level.
    $parent = Split-Path -Parent $Path
    if ($parent) {
        $leaf2 = Split-Path -Leaf $parent
        if ($leaf2 -match '^Claude_(\d+(?:\.\d+){1,3})_') {
            try { return [Version]$matches[1] } catch { return $null }
        }
    }
    return $null
}

function Save-PatchState {
    param([Parameter(Mandatory)][string]$InstallPath)
    try {
        if (-not (Test-Path $global:RtlStateDir)) {
            New-Item -ItemType Directory -Path $global:RtlStateDir -Force | Out-Null
        }
        $ver = Get-ClaudeVersionFromPath -Path $InstallPath
        $state = [ordered]@{
            patchedVersion     = if ($ver) { $ver.ToString() } else { $null }
            patchedInstallPath = $InstallPath
            patchedAt          = (Get-Date).ToUniversalTime().ToString("o")
        }
        $state | ConvertTo-Json | Set-Content -Path $global:RtlStateFile -Encoding UTF8
        Write-Log "Patch state recorded at $global:RtlStateFile (version: $($state.patchedVersion))"
    } catch {
        Write-Warn "Failed to save patch state: $($_.Exception.Message)"
    }
}

function Save-TrustedPubkey {
    # Pins the maintainer's PUBLIC KEY (the full RSA blob, not just a fingerprint
    # of it) to disk. The auto-update watcher loads this key directly and uses it
    # to verify patch.ps1.sig itself — install.ps1 is never fetched or executed
    # during auto-update. Storing the full key (instead of SHA-256 over the
    # blob, as the V1 design did) closes two bypasses of the V1 scheme:
    #   1. install.ps1 is unsigned. A V1 watcher fingerprint-matched only the
    #      $ExpectedPubKey variable, then ran the rest of install.ps1 as admin.
    #      A compromised repo could leave the pubkey untouched and ship a
    #      malicious payload around it. V2 never executes install.ps1.
    #   2. Regex extraction of $ExpectedPubKey is not equivalent to PowerShell's
    #      parser (commented-out lines, multiple assignments, here-strings).
    #      V2 reads the pubkey bytes from a local file, no parsing of remote
    #      script content involved.
    #
    # The pubkey value arrives via the CLAUDE_RTL_TRUSTED_PUBKEY env var set by
    # install.ps1 (first install) or by the watcher itself (subsequent
    # re-registrations). Using the env var rather than a fresh download avoids
    # a TOCTOU race where the repo could change between verification and pin.
    try {
        $pubB64 = $env:CLAUDE_RTL_TRUSTED_PUBKEY
        if (-not $pubB64) {
            Write-Warn "No CLAUDE_RTL_TRUSTED_PUBKEY env var; trusted-pubkey.b64 will not be written."
            Write-Warn "(Auto-update watcher will refuse to run without it -- this is the safe default.)"
            return
        }

        # Validate the blob is well-formed before pinning. A corrupt or
        # truncated env var would poison the pin and break legitimate updates.
        try {
            $pubJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pubB64))
            $pubObj  = $pubJson | ConvertFrom-Json
            $null = [Convert]::FromBase64String($pubObj.Modulus)
            $null = [Convert]::FromBase64String($pubObj.Exponent)
        } catch {
            Write-Warn "Trusted pubkey from env var failed to parse ($($_.Exception.Message)). Refusing to pin."
            return
        }

        if (-not (Test-Path $global:RtlStateDir)) {
            New-Item -ItemType Directory -Path $global:RtlStateDir -Force | Out-Null
        }
        $pinPath = Join-Path $global:RtlStateDir 'trusted-pubkey.b64'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($pinPath, $pubB64, $utf8NoBom)

        # Log a fingerprint so operators can cross-check against install.ps1 /
        # the README without exposing the full key blob in the log.
        $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash([Convert]::FromBase64String($pubB64))
        $fp  = ([BitConverter]::ToString($sha)).Replace('-', '').ToLower()
        Write-Log "Trusted pubkey pinned at $pinPath (sha256=$fp)"

        # Clean up the V1 fingerprint-only file. Harmless leftover but the V2
        # watcher no longer reads it; removing it avoids confusing future audits.
        $legacyFpr = Join-Path $global:RtlStateDir 'trusted-pubkey.fpr'
        if (Test-Path $legacyFpr) {
            Remove-Item $legacyFpr -Force -ErrorAction SilentlyContinue
            Write-Log "Removed legacy V1 pin file: trusted-pubkey.fpr"
        }
    } catch {
        Write-Warn "Save-TrustedPubkey failed: $($_.Exception.Message)"
    }
}

function Save-UpdateScript {
    # Writes a small local helper to %ProgramData%\ClaudeRtlPatch\update.ps1
    # used by the desktop "Update Claude RTL" shortcut. The helper does the
    # SAME verify-then-run dance the auto-update watcher does:
    #   1. Loads the pinned pubkey from trusted-pubkey.b64.
    #   2. Downloads patch.ps1 + patch.ps1.sig from GitHub.
    #   3. Verifies the RSA signature with the pinned key.
    #   4. Elevates via UAC and runs patch.ps1 -Auto directly.
    #
    # The whole point is to keep manual updates off the install.ps1 codepath.
    # install.ps1 itself is unsigned, so a compromised repo could ship a
    # malicious install.ps1 that runs as admin once the user clicks the
    # shortcut (UAC notwithstanding -- the user expects an update prompt and
    # would consent). With this helper, the shortcut launches LOCAL code only;
    # the only network artifact we trust is patch.ps1 + its signature.
    #
    # The helper is written as admin (this function only runs from Install-Patch
    # or Install-AutoUpdateTask, both elevated), so non-admin users cannot
    # tamper with it later -- the file inherits ProgramData ACLs where files
    # are owned by their elevated creator.
    try {
        if (-not (Test-Path $global:RtlStateDir)) {
            New-Item -ItemType Directory -Path $global:RtlStateDir -Force | Out-Null
        }
        $updatePath = Join-Path $global:RtlStateDir 'update.ps1'

        # Single-quoted here-string: $ signs are preserved literally for runtime evaluation.
        $updateBody = @'
# AI RTL Fix -- verified local updater.
#
# Loaded by the desktop "Update Claude RTL" shortcut. Uses the pubkey pinned
# at install time to verify patch.ps1 against the maintainer's offline private
# key, then elevates via UAC. install.ps1 is intentionally NOT used here --
# a compromised GitHub repo cannot influence this path.
$ErrorActionPreference = "Continue"
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$stateDir      = Join-Path $env:ProgramData "ClaudeRtlPatch"
$pubkeyPinFile = Join-Path $stateDir "trusted-pubkey.b64"
$repoBase      = "https://raw.githubusercontent.com/Ben-Boaron0/ai-rtl-fix/main"
$patchUrl      = "$repoBase/patch.ps1"
$sigUrl        = "$repoBase/patch.ps1.sig"

function Pause-ThenExit($code) {
    Write-Host ""
    Write-Host "Press Enter to close this window..." -ForegroundColor DarkGray
    $null = Read-Host
    Exit $code
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  AI RTL Fix -- verified update                        " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $pubkeyPinFile)) {
    Write-Host "No pinned pubkey at $pubkeyPinFile." -ForegroundColor Red
    Write-Host "This computer has not bootstrapped a trust anchor yet." -ForegroundColor Yellow
    Write-Host "Run the manual installer once to fix this:" -ForegroundColor Yellow
    Write-Host "  irm https://raw.githubusercontent.com/Ben-Boaron0/ai-rtl-fix/main/install.ps1 | iex" -ForegroundColor Cyan
    Pause-ThenExit 1
}

try {
    $pubB64 = (Get-Content $pubkeyPinFile -Raw).Trim()
    if (-not $pubB64) { throw "Pinned pubkey file is empty." }
    $pubJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pubB64))
    $pubObj  = $pubJson | ConvertFrom-Json
    $params = New-Object System.Security.Cryptography.RSAParameters
    $params.Modulus  = [Convert]::FromBase64String($pubObj.Modulus)
    $params.Exponent = [Convert]::FromBase64String($pubObj.Exponent)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportParameters($params)
} catch {
    Write-Host "Pinned pubkey is unreadable: $($_.Exception.Message)" -ForegroundColor Red
    Pause-ThenExit 1
}

Write-Host "Downloading patch.ps1 + signature..." -ForegroundColor Gray
try {
    $wc = New-Object System.Net.WebClient
    $patchBytes = $wc.DownloadData($patchUrl)
    $sigB64     = $wc.DownloadString($sigUrl).Trim()
} catch {
    Write-Host "Network error: $($_.Exception.Message)" -ForegroundColor Red
    Pause-ThenExit 1
}

try {
    $sigBytes = [Convert]::FromBase64String($sigB64)
} catch {
    Write-Host "Downloaded signature is not valid base64. Aborting." -ForegroundColor Red
    Pause-ThenExit 1
}

$valid = $rsa.VerifyData($patchBytes, $sigBytes,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

if (-not $valid) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  SIGNATURE VERIFICATION FAILED -- REFUSING TO RUN patch.ps1     " -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "patch.ps1 does not match the pinned maintainer key." -ForegroundColor Yellow
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  * The GitHub repository was compromised." -ForegroundColor Yellow
    Write-Host "  * The maintainer rotated keys (requires a manual re-install)." -ForegroundColor Yellow
    Write-Host "  * A proxy is intercepting traffic." -ForegroundColor Yellow
    Pause-ThenExit 1
}

# Strip incoming BOM (we re-add UTF-8 BOM on write). PS 5.1 needs BOM to parse
# Hebrew/box-drawing characters in patch.ps1.
$tmpFile = Join-Path $env:TEMP "ai_rtl_fix_patch.ps1"
$content = [System.Text.Encoding]::UTF8.GetString($patchBytes)
if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
[System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.UTF8Encoding]::new($true))

Write-Host "Patch verified ($($patchBytes.Length) bytes). Elevating..." -ForegroundColor Green

# Pass the pinned pubkey as a -TrustedPubKey PARAMETER so the elevated child's
# Save-TrustedPubkey sees the SAME trust anchor. An env var would NOT survive the
# Start-Process -Verb RunAs UAC boundary. CLAUDE_RTL_AUTO=1 tells patch.ps1 to run
# Install-Patch directly instead of showing the menu (the "1-click update" path).
$env:CLAUDE_RTL_AUTO = '1'

# Elevate via UAC. patch.ps1's Auto mode pauses on Read-Host at the end, so
# the user gets a chance to read the patch log before the window closes.
Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Verb RunAs `
    -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$tmpFile,'-Auto','-TrustedPubKey',$pubB64
    )
'@

        # PS 5.1 needs UTF-8 with BOM to parse Unicode text correctly.
        [System.IO.File]::WriteAllText($updatePath, $updateBody, [System.Text.UTF8Encoding]::new($true))
        Write-Log "Verified-update helper written to $updatePath"
    } catch {
        Write-Warn "Save-UpdateScript failed: $($_.Exception.Message)"
    }
}

