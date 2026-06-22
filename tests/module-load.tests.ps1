$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$expectedModuleDirs = @(
    'src/core',
    'src/apps/codex'
)

foreach ($moduleDir in $expectedModuleDirs) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $moduleDir)) "Expected module directory '$moduleDir' to exist."
}

$expectedFunctions = @(
    'Find-CodexDir',
    'Get-CodexInstallInspection',
    'Get-CodexAsarInspection',
    'Show-CodexInspection',
    'Get-CodexRtlPayload',
    'Install-CodexRtlPatch',
    'Restore-CodexRtlPatch',
    'Launch-CodexRtl',
    'Show-Menu'
)

foreach ($functionName in $expectedFunctions) {
    Assert-True ([bool](Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) "Expected function '$functionName' to be loaded by patch.ps1 -SkipMain."
}

$unexpectedFunctions = @(
    ('Find-' + ('Cl' + 'aude') + 'Dir'),
    ('Get-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'Config'),
    ('Get-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'InstallerText'),
    ('Get-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'PublicKeyFromInstaller'),
    ('Save-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'VerifiedPatch'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'PatchFile'),
    ('Get-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'MenuInput'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'Patch'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'Restore'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'QuickUpdate'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'EnableAuto'),
    ('Invoke-' + ('Cl' + 'aude') + ('Up' + 'stream') + 'DisableAuto')
)

foreach ($functionName in $unexpectedFunctions) {
    Assert-True (-not [bool](Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) "Function '$functionName' should not be loaded in the Codex-only build."
}

Assert-True (-not [bool](Get-Command -Name Start-CodexWithRtlActivation -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not include the failed Store activation experiment.'
Assert-True (-not [bool](Get-Command -Name Restart-CodexForRtl -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose a separate restart-only helper.'
Assert-True (-not [bool](Get-Command -Name New-CodexRtlStartProcessSpec -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose launch spec assembly as a public helper.'
Assert-True (-not [bool](Get-Command -Name New-CodexRuntimeEvaluateCommand -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose CDP command-builder helpers publicly.'

Write-Host 'module-load.tests.ps1 passed'
