$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

$script:Calls = @()
$script:Output = @()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Reset-TestState {
    $script:Calls = @()
    $script:Output = @()
    $script:Prompts = @()
}

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        [ConsoleColor]$ForegroundColor
    )
    if ($null -ne $Object) {
        $script:Output += (($Object | ForEach-Object { "$_" }) -join ' ')
    }
}

function Clear-Host {}
function Start-Sleep { param([int]$Seconds) }
function Read-Host { param([string]$Prompt) return '' }

function Install-CodexRtlPatch { $script:Calls += 'Install-CodexRtlPatch' }
function Restore-CodexRtlPatch { $script:Calls += 'Restore-CodexRtlPatch' }

function New-TestApp {
    param(
        [string]$Id,
        [string]$Name,
        [bool]$Found = $true,
        [string]$SupportStatus = 'Supported',
        [bool]$Selected = $true
    )

    [pscustomobject]@{
        Id = $Id
        Name = $Name
        Found = $Found
        SupportStatus = $SupportStatus
        InstallLocation = if ($Found) { "C:\Fake\$Id" } else { $null }
        Selected = $Selected
        Selectable = $Found -and $SupportStatus -ne 'Planned'
    }
}

Assert-True ([bool](Get-Command -Name Show-Menu -CommandType Function -ErrorAction SilentlyContinue)) 'Show-Menu should load.'
Assert-True ([bool](Get-Command -Name Invoke-SelectedAppAction -CommandType Function -ErrorAction SilentlyContinue)) 'Action dispatcher should load.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Patch'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-CodexRtlPatch' }).Count 'Codex patch should dispatch runtime RTL patch.'
Assert-True (($script:Prompts | Where-Object { $_ -match '\(y/n\)' }).Count -eq 1) 'Codex patch confirmation should use lowercase y/n wording.'
Assert-True (($script:Output | Where-Object { $_ -match 'automatically close and relaunch Codex if it is currently open' }).Count -eq 1) 'Codex patch warning should clearly state that open Codex sessions will be relaunched.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Restore'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Restore-CodexRtlPatch' }).Count 'Codex restore should dispatch runtime RTL restore.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'n'
}
Invoke-SelectedAppAction -ActionId 'Restore'
Assert-Equal 0 @($script:Calls | Where-Object { $_ -eq 'Restore-CodexRtlPatch' }).Count 'Codex restore should honor cancellation.'
Assert-True (($script:Prompts | Where-Object { $_ -match 'continue' }).Count -eq 1) 'Codex restore should use the standard confirmation prompt.'

Reset-TestState
$script:MenuInputs = [System.Collections.Generic.Queue[string]]::new()
$script:MenuInputs.Enqueue('')
$script:MenuInputs.Enqueue('abc')
$script:MenuInputs.Enqueue('y')
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    if ($script:MenuInputs.Count -eq 0) { throw 'No test input left.' }
    return $script:MenuInputs.Dequeue()
}
Invoke-SelectedAppAction -ActionId 'Patch'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-CodexRtlPatch' }).Count 'Codex patch should treat Enter as yes for the confirmation prompt.'
Assert-Equal 1 @($script:Prompts | Where-Object { $_ -match 'continue' }).Count 'Empty confirmation input should not re-prompt when yes is the default.'

Reset-TestState
function Read-Host { param([string]$Prompt) return '' }

$detectedAppNames = @(Get-DetectedApps | ForEach-Object { $_.Name })
Assert-Equal 1 $detectedAppNames.Count 'Detected app list should include exactly one active app target.'
Assert-Equal 'Codex Desktop' $detectedAppNames[0] 'Detected app target should be Codex Desktop only.'

Reset-TestState
$script:MenuInputs = [System.Collections.Generic.Queue[string]]::new()
$script:MenuInputs.Enqueue('3')
function Read-Host {
    param([string]$Prompt)
    if ($script:MenuInputs.Count -eq 0) { throw 'No test input left.' }
    return $script:MenuInputs.Dequeue()
}
Show-Menu
Assert-Equal 0 $script:Calls.Count 'Exit should leave the menu without dispatching actions.'

Write-Host 'menu-flow.tests.ps1 passed'
