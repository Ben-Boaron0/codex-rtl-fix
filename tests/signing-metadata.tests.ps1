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
$readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw

$expectedRepoBase = 'https://raw.githubusercontent.com/Ben-Boaron0/codex-rtl-fix/main'

Assert-Match $install ([regex]::Escape($expectedRepoBase)) 'install.ps1 should download from Codex RTL Fix.'
Assert-Match $patch ([regex]::Escape($expectedRepoBase + '/install.ps1')) 'patch.ps1 bootstrap fallback should use Codex RTL Fix install.ps1.'
Assert-Match $readme ([regex]::Escape('irm https://raw.githubusercontent.com/Ben-Boaron0/codex-rtl-fix/main/install.ps1 | iex')) 'README should document the public Codex RTL Fix one-line installer.'
Assert-Match $readme 'Codex RTL' 'README should explain the Codex RTL shortcut behavior.'
Assert-Match $install 'src/core/logging\.ps1' 'install.ps1 should download the module tree needed by patch.ps1.'
Assert-Match $install 'New-Item -ItemType Directory' 'install.ps1 should create module directories in the temp patch folder.'
Assert-Match $patch 'CodexRtlFixModuleManifest' 'Signed patch.ps1 should pin hashes for downloaded modules.'
Assert-Match $patch 'Get-FileHash' 'patch.ps1 should verify module hashes before loading modules.'
Assert-Match $signRelease '\.codex-rtl-fix-signing\.key' 'sign-release.ps1 should default to the Codex RTL Fix private key.'
Assert-Match $install 'Codex RTL Fix' 'install.ps1 should use Codex RTL Fix branding.'
Assert-Match $readme 'Public-key fingerprint' 'README should document the signing fingerprint.'

foreach ($activeContent in @($install, $patch)) {
    Assert-NotMatch $activeContent (('cl' + 'aude')) 'Active updater/install code should not reference removed app code.'
    Assert-NotMatch $activeContent (('ai' + '-' + 'rtl' + '-' + 'fix')) 'Active updater/install code should not reference the old repo slug.'
}

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'tools\new-signing-key.ps1')) 'tools/new-signing-key.ps1 should exist.'

$verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\verify-signature.ps1') 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "tools/verify-signature.ps1 failed:`n$($verify | Out-String)"
}

Write-Host 'signing-metadata.tests.ps1 passed'
