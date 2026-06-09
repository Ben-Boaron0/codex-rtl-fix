$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw "$Message Pattern '$Pattern' was not found."
    }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw "$Message Pattern '$Pattern' should not be present."
    }
}

$install = Get-Content (Join-Path $repoRoot 'install.ps1') -Raw
$patch = Get-Content (Join-Path $repoRoot 'patch.ps1') -Raw
$signRelease = Get-Content (Join-Path $repoRoot 'tools\sign-release.ps1') -Raw
$stateModule = Get-Content (Join-Path $repoRoot 'src\apps\claude\state.ps1') -Raw
$patchingModule = Get-Content (Join-Path $repoRoot 'src\apps\claude\patching.ps1') -Raw
$readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw
$diagPath = Join-Path $repoRoot 'tools\claude-lock-diag.ps1'

$expectedRepoBase = 'https://raw.githubusercontent.com/Ben-Boaron0/ai-rtl-fix/main'

Assert-Match $install ([regex]::Escape($expectedRepoBase)) 'install.ps1 should download from AI RTL Fix.'
Assert-Match $patch ([regex]::Escape($expectedRepoBase + '/install.ps1')) 'patch.ps1 bootstrap fallback should use AI RTL Fix install.ps1.'
Assert-Match $stateModule ([regex]::Escape($expectedRepoBase)) 'Generated update helper should fetch from AI RTL Fix.'
Assert-Match $patchingModule ([regex]::Escape($expectedRepoBase)) 'Generated watcher should fetch from AI RTL Fix.'
Assert-Match $signRelease '\.ai-rtl-fix-signing\.key' 'sign-release.ps1 should default to the AI RTL Fix private key.'
Assert-Match $install 'AI RTL Fix' 'install.ps1 should use AI RTL Fix branding.'
Assert-Match $readme 'Public-key fingerprint' 'README should document the signing fingerprint.'

foreach ($activeContent in @($install, $patch, $stateModule, $patchingModule)) {
    Assert-NotMatch $activeContent 'raw\.githubusercontent\.com/shraga100/claude-desktop-rtl-patch/main' 'Active updater/install URLs should not point to the upstream Claude project.'
}

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'tools\new-signing-key.ps1')) 'tools/new-signing-key.ps1 should exist.'
Assert-True (Test-Path -LiteralPath $diagPath) 'tools/claude-lock-diag.ps1 should exist.'

$diag = Get-Content $diagPath -Raw
Assert-Match $diag 'AI RTL Fix' 'Claude lock diagnostic should use AI RTL Fix branding.'
Assert-NotMatch $diag 'Please attach that file to GitHub issue #15' 'Diagnostic should not include upstream issue-upload instructions.'

$verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\verify-signature.ps1') 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "tools/verify-signature.ps1 failed:`n$($verify | Out-String)"
}

Write-Host 'signing-metadata.tests.ps1 passed'
