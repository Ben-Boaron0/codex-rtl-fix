$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw "$Message Pattern '$Pattern' should not be present."
    }
}

Assert-True ([bool](Get-Variable -Name RTL_INJECTION_CODE -Scope Global -ErrorAction SilentlyContinue) -or [bool](Get-Variable -Name RTL_INJECTION_CODE -Scope Script -ErrorAction SilentlyContinue)) 'RTL payload should load.'
Assert-True ([bool](Get-Variable -Name MAIN_INJECTION_CODE -Scope Global -ErrorAction SilentlyContinue) -or [bool](Get-Variable -Name MAIN_INJECTION_CODE -Scope Script -ErrorAction SilentlyContinue)) 'Main-process payload should load.'

Assert-NotMatch $RTL_INJECTION_CODE 'CLAUDE WCO FIX START' 'Renderer payload should no longer include the old WCO padding fix.'
Assert-NotMatch $RTL_INJECTION_CODE 'windowControlsOverlay' 'Renderer payload should not rely on Window Controls Overlay.'

Assert-True ($MAIN_INJECTION_CODE -match 'force-ui-direction') 'Main-process payload should force Chromium UI direction.'
Assert-True ($MAIN_INJECTION_CODE -match "appendSwitch\('force-ui-direction', 'ltr'\)") 'Main-process payload should append force-ui-direction=ltr.'
Assert-NotMatch $MAIN_INJECTION_CODE '\bdocument\b|\bwindow\b|\bnavigator\b' 'Main-process payload should remain DOM-free.'

$patchingSource = Get-Content (Join-Path $repoRoot 'src\apps\claude\patching.ps1') -Raw
Assert-True ($patchingSource -match 'ConvertFrom-Json\)\.main') 'ASAR patching should resolve the Electron main entry from package.json.'
Assert-True ($patchingSource -match 'node --check') 'ASAR patching should syntax-check the patched main entry before repacking.'
foreach ($name in @('index.js', 'directMcpHost.js', 'nodeHost.js', 'shellPathWorker.js', 'transcriptSearchWorker.js')) {
    Assert-True ($patchingSource.Contains("'$name'")) "Non-renderer skip list should contain $name."
}
Assert-True ($patchingSource -match '\$SkipEntirely = @\([\s\S]*''index\.pre\.js''[\s\S]*\)') 'Non-renderer skip list should contain index.pre.js when it is not the resolved main entry.'
Assert-True ($patchingSource -match '\$content -match "CLAUDE RTL MAIN PATCH START"') 'Main entry should be idempotently patched.'
Assert-True ($patchingSource -match '\$strictRe') 'Main entry injection should preserve a leading use-strict directive.'
Assert-True ($patchingSource -match '\$file\.Name -ne \$MainEntryFile') 'Resolved main entry should not be skipped even if its filename appears in the non-renderer skip list.'
Assert-True ($patchingSource -match '\$MainSeen') 'Main entry reporting should track whether the main entry was found.'
Assert-True ($patchingSource -match '\$MainAlreadyPatched') 'Main entry reporting should distinguish already-patched entries from missing entries.'

Write-Host 'claude-main-injection.tests.ps1 passed'
