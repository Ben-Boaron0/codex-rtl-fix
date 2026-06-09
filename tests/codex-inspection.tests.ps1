$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

$script:Output = @()

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        [ConsoleColor]$ForegroundColor
    )
    if ($null -ne $Object) {
        $script:Output += (($Object | ForEach-Object { "$_" }) -join ' ')
    }
}

function New-TestAsar {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$IndexHtml
    )

    $indexBytes = [System.Text.Encoding]::UTF8.GetBytes($IndexHtml)
    $headerObject = [ordered]@{
        files = [ordered]@{
            webview = [ordered]@{
                files = [ordered]@{
                    'index.html' = [ordered]@{
                        size = $indexBytes.Length
                        offset = '0'
                        integrity = [ordered]@{ algorithm = 'SHA256'; hash = 'test' }
                    }
                    assets = [ordered]@{
                        files = [ordered]@{
                            'index-test.js' = [ordered]@{ size = 1; offset = "$($indexBytes.Length)" }
                            'app-main-test.css' = [ordered]@{ size = 1; offset = "$($indexBytes.Length + 1)" }
                            'composer-test.js' = [ordered]@{ size = 1; offset = "$($indexBytes.Length + 2)" }
                        }
                    }
                }
            }
        }
    }

    $headerJson = $headerObject | ConvertTo-Json -Depth 20 -Compress
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerJson)

    $fs = [System.IO.File]::Open($Path, 'Create', 'Write', 'None')
    try {
        $bw = [System.IO.BinaryWriter]::new($fs)
        $bw.Write([uint32]0)
        $bw.Write([uint32]0)
        $bw.Write([uint32]0)
        $bw.Write([uint32]$headerBytes.Length)
        $bw.Write($headerBytes)
        $bw.Write($indexBytes)
        $bw.Write([byte]0x61)
        $bw.Write([byte]0x62)
        $bw.Write([byte]0x63)
    } finally {
        $fs.Close()
    }
}

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

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-inspection-test-{0}.asar" -f ([guid]::NewGuid()))
try {
    New-TestAsar -Path $tmp -IndexHtml '<!doctype html><meta http-equiv="Content-Security-Policy" content="script-src ''self''; style-src ''self'' ''unsafe-inline''"><script type="module" src="./assets/index-test.js"></script>'

    $analysis = Get-CodexAsarInspection -AsarPath $tmp

    Assert-True $analysis.AsarExists 'ASAR should be detected.'
    Assert-True $analysis.IndexHtmlFound 'webview/index.html should be found.'
    Assert-True $analysis.ExternalScriptInjectionAllowed 'CSP should allow same-origin external scripts.'
    Assert-True $analysis.AsarIntegrityMetadataPresent 'Integrity metadata should be detected.'
    Assert-True (@($analysis.RendererScripts) -contains 'webview/assets/index-test.js') 'Renderer script should be listed.'
    Assert-True (@($analysis.RendererStyles) -contains 'webview/assets/app-main-test.css') 'Renderer stylesheet should be listed.'

    Assert-True (Test-CspAllowsExternalSelfScript '<meta http-equiv="Content-Security-Policy" content="script-src ''self'' ''wasm-unsafe-eval''; style-src ''self'' ''unsafe-inline''">') 'CSP parser should allow quoted self in double-quoted content attributes.'
    Assert-True (Test-CspAllowsExternalSelfScript '<meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; script-src &#39;self&#39; &#39;wasm-unsafe-eval&#39;">') 'CSP parser should decode HTML entities before checking script-src.'

    function Get-CodexInstallInspection {
        [pscustomobject]@{
            PackageFound = $true
            PackageName = 'OpenAI.Codex'
            PackageVersion = '1.2.3'
            InstallLocation = 'C:\Fake\OpenAI.Codex'
            AppExe = 'C:\Fake\OpenAI.Codex\app\Codex.exe'
            AsarPath = $tmp
            AsarInspection = $analysis
        }
    }
    function Get-CodexHashEmbeddingReport {
        param([Parameter(Mandatory)]$Inspection)
        [pscustomobject]@{
            HeaderSha256 = 'header'
            FullAsarSha256 = 'full'
            Targets = @(
                [pscustomobject]@{
                    Name = 'Codex.exe'
                    Exists = $true
                    HeaderHashFound = $false
                    FullAsarHashFound = $false
                }
            )
        }
    }

    $script:Output = @()
    Show-CodexInspection
    Assert-True (-not (($script:Output -join "`n") -match 'Recommendation:')) 'Inspection output should not include a Recommendation section.'
    Assert-True (-not (($script:Output -join "`n") -match 'runtime CDP injection')) 'Inspection output should not print the old phase-two recommendation text.'

    Write-Host 'codex-inspection.tests.ps1 passed'
} finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }
}
