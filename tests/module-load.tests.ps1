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
    'src/apps/claude',
    'src/apps/codex'
)

foreach ($moduleDir in $expectedModuleDirs) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $moduleDir)) "Expected module directory '$moduleDir' to exist."
}

$expectedFunctions = @(
    'Find-ClaudeDir',
    'Install-Patch',
    'Restore-Patch',
    'Install-AutoUpdateTask',
    'Uninstall-AutoUpdateTask',
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

Assert-True (-not [bool](Get-Command -Name Install-CodexRtlShortcut -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not create a duplicate Start Menu shortcut helper.'
Assert-True (-not [bool](Get-Command -Name Start-CodexWithRtlActivation -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not include the failed Store activation experiment.'
Assert-True (-not [bool](Get-Command -Name Restart-CodexForRtl -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose a separate restart-only helper.'
Assert-True (-not [bool](Get-Command -Name New-CodexRtlStartProcessSpec -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose launch spec assembly as a public helper.'
Assert-True (-not [bool](Get-Command -Name New-CodexRuntimeEvaluateCommand -CommandType Function -ErrorAction SilentlyContinue)) 'Codex patch should not expose CDP command-builder helpers publicly.'

Write-Host 'module-load.tests.ps1 passed'
