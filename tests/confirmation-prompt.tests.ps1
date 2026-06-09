$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

$script:Prompts = @()
$script:Inputs = [System.Collections.Generic.Queue[string]]::new()
$script:Calls = @()

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

function Read-Host {
    param([string]$Prompt)
    if ($Prompt) { $script:Prompts += $Prompt }
    if ($script:Inputs.Count -eq 0) { throw 'No test input left.' }
    return $script:Inputs.Dequeue()
}

$script:Inputs.Enqueue('')
Assert-True (Read-YesNoPrompt -Prompt 'Do you want to continue? (Y/n)') 'Read-YesNoPrompt should treat Enter as yes for Y/n prompts.'
Assert-Equal 1 $script:Prompts.Count 'Read-YesNoPrompt should not re-prompt after Enter when yes is the default.'
Assert-Equal 0 (@($script:Prompts | Where-Object { $_ -notmatch '\(Y/n\)' }).Count) 'Read-YesNoPrompt should preserve Y/n prompt wording.'

$script:Prompts = @()
$script:Inputs = [System.Collections.Generic.Queue[string]]::new()
$script:Inputs.Enqueue('maybe')
$script:Inputs.Enqueue('Y')
Assert-True (Read-YesNoPrompt -Prompt 'Do you want to continue? (Y/n)') 'Read-YesNoPrompt should accept uppercase Y after retrying invalid input.'
Assert-Equal 2 $script:Prompts.Count 'Read-YesNoPrompt should keep prompting after invalid input until a valid answer is entered.'

$script:Prompts = @()
$script:Inputs = [System.Collections.Generic.Queue[string]]::new()
$script:Inputs.Enqueue('')
Assert-True (Read-YesNoPrompt -Prompt 'Do you want to enable Auto Re-Patch after each Claude update? (Y/n)') 'Read-YesNoPrompt should use yes as the default for auto-repatch prompts.'

Write-Host 'confirmation-prompt.tests.ps1 passed'
