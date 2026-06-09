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

function Install-Patch { $script:Calls += 'Install-Patch' }
function Restore-Patch { $script:Calls += 'Restore-Patch' }
function Create-UpdateShortcut { $script:Calls += 'Create-UpdateShortcut' }
function Install-AutoUpdateTask { $script:Calls += 'Install-AutoUpdateTask' }
function Uninstall-AutoUpdateTask { $script:Calls += 'Uninstall-AutoUpdateTask' }
function Show-CodexInspection { $script:Calls += 'Show-CodexInspection' }
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
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'claude' -Name 'Claude Desktop'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Claude patch should dispatch once.'
Assert-True (($script:Prompts | Where-Object { $_ -match '\(y/n\)' }).Count -eq 1) 'Claude patch confirmation should use lowercase y/n wording.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Restore' -SelectedApps @((New-TestApp -Id 'claude' -Name 'Claude Desktop'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Restore-Patch' }).Count 'Claude restore should dispatch once.'

Reset-TestState
Invoke-SelectedAppAction -ActionId 'Inspect' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Show-CodexInspection' }).Count 'Codex inspect should dispatch once.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 0 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Codex patch should not dispatch Claude patch.'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-CodexRtlPatch' }).Count 'Codex patch should dispatch runtime RTL patch.'
Assert-True (($script:Prompts | Where-Object { $_ -match '\(y/n\)' }).Count -eq 1) 'Codex patch confirmation should use lowercase y/n wording.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Restore' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 0 @($script:Calls | Where-Object { $_ -eq 'Restore-Patch' }).Count 'Codex restore should not dispatch Claude restore.'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Restore-CodexRtlPatch' }).Count 'Codex restore should dispatch runtime RTL restore.'

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'n'
}
Invoke-SelectedAppAction -ActionId 'Restore' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
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
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-CodexRtlPatch' }).Count 'Codex patch should execute after invalid confirmation inputs are retried and then answered with y.'
Assert-Equal 3 @($script:Prompts | Where-Object { $_ -match 'continue' }).Count 'Invalid confirmation inputs should re-prompt until a valid y/n answer is entered.'

Reset-TestState
$script:MenuInputs = [System.Collections.Generic.Queue[string]]::new()
$script:MenuInputs.Enqueue('')
$script:MenuInputs.Enqueue('n')
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    if ($script:MenuInputs.Count -eq 0) { throw 'No test input left.' }
    return $script:MenuInputs.Dequeue()
}
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'claude' -Name 'Claude Desktop'))
Assert-Equal 0 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Claude patch should not treat Enter as implicit yes.'
Assert-Equal 2 @($script:Prompts | Where-Object { $_ -match 'continue' }).Count 'Empty confirmation input should re-prompt before accepting n cancellation.'
function Read-Host { param([string]$Prompt) return '' }

Reset-TestState
function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    return 'y'
}
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @(
    (New-TestApp -Id 'claude' -Name 'Claude Desktop'),
    (New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned')
)
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Claude patch should dispatch once with mixed selection.'
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-CodexRtlPatch' }).Count 'Mixed patch should dispatch Codex runtime RTL once.'

$detectedAppNames = @(Get-DetectedApps | ForEach-Object { $_.Name })
Assert-Equal 2 $detectedAppNames.Count 'Detected app list should include exactly the active app targets.'
Assert-True (-not [bool]($detectedAppNames | Where-Object { $_ -notin @('Claude Desktop', 'Codex Desktop') })) 'Detected app list should only include active app targets.'

Reset-TestState
$script:MenuInputs = [System.Collections.Generic.Queue[string]]::new()
$script:MenuInputs.Enqueue('Q')
function Read-Host {
    param([string]$Prompt)
    if ($script:MenuInputs.Count -eq 0) { throw 'No test input left.' }
    return $script:MenuInputs.Dequeue()
}
Show-Menu
Assert-Equal 0 $script:Calls.Count 'Q should exit menu without dispatching actions.'

Write-Host 'menu-flow.tests.ps1 passed'
