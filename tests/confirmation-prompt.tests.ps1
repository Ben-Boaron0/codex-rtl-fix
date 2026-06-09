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
$script:Inputs.Enqueue('maybe')
$script:Inputs.Enqueue('Y')
Assert-True (Read-YesNoPrompt -Prompt 'Do you want to continue? (y/n)') 'Read-YesNoPrompt should accept uppercase Y after retrying invalid input.'
Assert-Equal 3 $script:Prompts.Count 'Read-YesNoPrompt should keep prompting until a valid answer is entered.'
Assert-Equal 0 (@($script:Prompts | Where-Object { $_ -notmatch '\(y/n\)' }).Count) 'Read-YesNoPrompt should preserve lowercase y/n prompt wording on retries.'

$script:Prompts = @()
$script:Inputs = [System.Collections.Generic.Queue[string]]::new()
$script:Inputs.Enqueue('')
$script:Inputs.Enqueue('n')
Assert-True (-not (Read-YesNoPrompt -Prompt 'Do you want to enable Auto Re-Patch after each Claude update? (y/n)')) 'Read-YesNoPrompt should return false after empty input is retried and n is entered.'
Assert-Equal 2 $script:Prompts.Count 'Read-YesNoPrompt should re-prompt after empty input before accepting n.'

Write-Host 'confirmation-prompt.tests.ps1 passed'
