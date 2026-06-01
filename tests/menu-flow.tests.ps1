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

function Install-Patch { $script:Calls += 'Install-Patch' }
function Restore-Patch { $script:Calls += 'Restore-Patch' }
function Create-UpdateShortcut { $script:Calls += 'Create-UpdateShortcut' }
function Install-AutoUpdateTask { $script:Calls += 'Install-AutoUpdateTask' }
function Uninstall-AutoUpdateTask { $script:Calls += 'Uninstall-AutoUpdateTask' }
function Show-CodexInspection { $script:Calls += 'Show-CodexInspection' }

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
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'claude' -Name 'Claude Desktop'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Claude patch should dispatch once.'

Reset-TestState
Invoke-SelectedAppAction -ActionId 'Restore' -SelectedApps @((New-TestApp -Id 'claude' -Name 'Claude Desktop'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Restore-Patch' }).Count 'Claude restore should dispatch once.'

Reset-TestState
Invoke-SelectedAppAction -ActionId 'Inspect' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Show-CodexInspection' }).Count 'Codex inspect should dispatch once.'

Reset-TestState
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @((New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned'))
Assert-Equal 0 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Codex patch should not dispatch Claude patch.'
Assert-True (($script:Output -join "`n") -match 'Codex Desktop.*patch not supported yet') 'Codex patch should print unsupported skip.'

Reset-TestState
Invoke-SelectedAppAction -ActionId 'Patch' -SelectedApps @(
    (New-TestApp -Id 'claude' -Name 'Claude Desktop'),
    (New-TestApp -Id 'codex' -Name 'Codex Desktop' -SupportStatus 'Planned')
)
Assert-Equal 1 @($script:Calls | Where-Object { $_ -eq 'Install-Patch' }).Count 'Claude patch should dispatch once with mixed selection.'
Assert-True (($script:Output -join "`n") -match 'Codex Desktop.*patch not supported yet') 'Mixed patch should skip Codex.'

$chatGpt = New-TestApp -Id 'chatgpt' -Name 'ChatGPT Desktop' -Found:$false -SupportStatus 'Planned' -Selected:$false
Assert-True (-not (Test-AppMenuSelectable -App $chatGpt)) 'ChatGPT should not be selectable.'

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
