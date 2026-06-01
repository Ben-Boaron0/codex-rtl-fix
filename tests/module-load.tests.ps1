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
    'Show-Menu'
)

foreach ($functionName in $expectedFunctions) {
    Assert-True ([bool](Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) "Expected function '$functionName' to be loaded by patch.ps1 -SkipMain."
}

Write-Host 'module-load.tests.ps1 passed'
