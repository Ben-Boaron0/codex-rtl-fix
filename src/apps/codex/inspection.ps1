function Get-CodexAsarInspection {
    param([Parameter(Mandatory)][string]$AsarPath)

    $result = [ordered]@{
        AsarPath = $AsarPath
        AsarExists = $false
        AsarSize = 0
        HeaderSha256 = $null
        IndexHtmlFound = $false
        ExternalScriptInjectionAllowed = $false
        CandidateInjectionPointFound = $false
        RendererScripts = @()
        RendererStyles = @()
        AsarIntegrityMetadataPresent = $false
        Error = $null
    }

    if (-not (Test-Path -LiteralPath $AsarPath)) {
        return [pscustomobject]$result
    }

    try {
        $item = Get-Item -LiteralPath $AsarPath -ErrorAction Stop
        $headerInfo = Read-AsarHeaderInfo -AsarPath $AsarPath
        $entryPaths = @(Get-AsarEntryPaths -Node $headerInfo.Header)
        $indexHtml = Get-AsarEntryText -AsarPath $AsarPath -HeaderInfo $headerInfo -ArchivePath 'webview/index.html'
        $rendererScripts = @($entryPaths | Where-Object { $_ -like 'webview/assets/*.js' } | Sort-Object)
        $rendererStyles = @($entryPaths | Where-Object { $_ -like 'webview/assets/*.css' } | Sort-Object)
        $allowsExternalScript = Test-CspAllowsExternalSelfScript -IndexHtml $indexHtml

        $result.AsarExists = $true
        $result.AsarSize = $item.Length
        $result.HeaderSha256 = $headerInfo.HeaderSha256
        $result.IndexHtmlFound = [bool]$indexHtml
        $result.ExternalScriptInjectionAllowed = $allowsExternalScript
        $result.CandidateInjectionPointFound = ([bool]$indexHtml -and $allowsExternalScript -and $rendererScripts.Count -gt 0)
        $result.RendererScripts = $rendererScripts
        $result.RendererStyles = $rendererStyles
        $result.AsarIntegrityMetadataPresent = Test-AsarIntegrityMetadataPresent -Node $headerInfo.Header
    } catch {
        $result.Error = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Get-CodexInstallInspection {
    $pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    $installLocation = if ($pkg) { $pkg.InstallLocation } else { $null }
    $appDir = if ($installLocation) { Join-Path $installLocation 'app' } else { $null }
    $resourcesDir = if ($appDir) { Join-Path $appDir 'resources' } else { $null }
    $appExe = if ($appDir) { Join-Path $appDir 'Codex.exe' } else { $null }
    $cliExe = if ($resourcesDir) { Join-Path $resourcesDir 'codex.exe' } else { $null }
    $asarPath = if ($resourcesDir) { Join-Path $resourcesDir 'app.asar' } else { $null }
    $asarInspection = if ($asarPath) { Get-CodexAsarInspection -AsarPath $asarPath } else { $null }

    return [pscustomobject]@{
        PackageFound = [bool]$pkg
        PackageName = if ($pkg) { $pkg.Name } else { $null }
        PackageVersion = if ($pkg) { $pkg.Version.ToString() } else { $null }
        InstallLocation = $installLocation
        AppExe = $appExe
        CliExe = $cliExe
        AsarPath = $asarPath
        AsarInspection = $asarInspection
    }
}

function Test-FileContainsAsciiText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Needle
    )

    if (-not (Test-Path -LiteralPath $Path) -or [string]::IsNullOrEmpty($Needle)) { return $false }
    $bufferSize = 1048576
    $overlapSize = [Math]::Max(0, $Needle.Length - 1)
    $previousText = ''
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $buffer = New-Object byte[] $bufferSize
        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $chunkText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            $combinedText = $previousText + $chunkText
            if ($combinedText.Contains($Needle)) {
                return $true
            }

            $keep = [Math]::Min($overlapSize, $combinedText.Length)
            if ($keep -gt 0) {
                $previousText = $combinedText.Substring($combinedText.Length - $keep)
            } else {
                $previousText = ''
            }
        }
    } finally {
        $fs.Close()
    }

    return $false
}

function Get-CodexHashEmbeddingReport {
    param([Parameter(Mandatory)]$Inspection)

    $headerHash = if ($Inspection.AsarInspection) { $Inspection.AsarInspection.HeaderSha256 } else { $null }
    $fullHash = $null
    if ($Inspection.AsarPath -and (Test-Path -LiteralPath $Inspection.AsarPath)) {
        $fullHash = (Get-FileHash -LiteralPath $Inspection.AsarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $targets = @(
        [pscustomobject]@{ Name = 'Codex.exe'; Path = $Inspection.AppExe },
        [pscustomobject]@{ Name = 'resources\codex.exe'; Path = $Inspection.CliExe }
    )

    $rows = @()
    foreach ($target in $targets) {
        $headerFound = $false
        $fullFound = $false
        if ($target.Path -and (Test-Path -LiteralPath $target.Path)) {
            if ($headerHash) { $headerFound = Test-FileContainsAsciiText -Path $target.Path -Needle $headerHash }
            if ($fullHash) { $fullFound = Test-FileContainsAsciiText -Path $target.Path -Needle $fullHash }
        }
        $rows += [pscustomobject]@{
            Name = $target.Name
            Path = $target.Path
            Exists = [bool]($target.Path -and (Test-Path -LiteralPath $target.Path))
            HeaderHashFound = $headerFound
            FullAsarHashFound = $fullFound
        }
    }

    return [pscustomobject]@{
        HeaderSha256 = $headerHash
        FullAsarSha256 = $fullHash
        Targets = $rows
    }
}

function Get-CodexPhaseTwoRecommendation {
    param([Parameter(Mandatory)]$Inspection)

    if (-not $Inspection.AsarExists) {
        return 'Do not patch yet: app.asar was not found.'
    }
    if ($Inspection.Error) {
        return "Do not patch yet: ASAR inspection failed ($($Inspection.Error))."
    }
    if (-not $Inspection.IndexHtmlFound) {
        return 'Do not patch yet: webview/index.html was not found.'
    }
    if (-not $Inspection.ExternalScriptInjectionAllowed) {
        return 'Do not use simple external JS injection yet: Content-Security-Policy does not allow same-origin scripts.'
    }
    if (-not $Inspection.CandidateInjectionPointFound) {
        return 'Do not patch yet: renderer assets were not found next to webview/index.html.'
    }
    return 'Phase two should use runtime CDP injection so Codex Store package files are not modified.'
}

function Show-CodexInspection {
    Write-Host "`nCodex Desktop inspection (read-only)" -ForegroundColor Cyan
    Write-Host "No files will be modified, no processes will be started, and no scheduled tasks will be changed." -ForegroundColor DarkGray

    $inspection = Get-CodexInstallInspection
    if (-not $inspection.PackageFound) {
        Write-Host "`nCodex Desktop was not found on this system." -ForegroundColor Yellow
        return
    }

    Write-Host "`nPackage:" -ForegroundColor White
    Write-Host "  Name:    $($inspection.PackageName)"
    Write-Host "  Version: $($inspection.PackageVersion)"
    Write-Host "  Path:    $($inspection.InstallLocation)"
    Write-Host "  App exe: $($inspection.AppExe)"
    Write-Host "  ASAR:    $($inspection.AsarPath)"

    $asar = $inspection.AsarInspection
    Write-Host "`nASAR:" -ForegroundColor White
    if (-not $asar -or -not $asar.AsarExists) {
        Write-Host "  app.asar: Missing" -ForegroundColor Red
        return
    }

    Write-Host ("  app.asar: Present ({0:N0} bytes)" -f $asar.AsarSize) -ForegroundColor Green
    Write-Host "  webview/index.html: $(if ($asar.IndexHtmlFound) { 'Found' } else { 'Missing' })"
    Write-Host "  External script allowed by CSP: $(if ($asar.ExternalScriptInjectionAllowed) { 'Yes' } else { 'No' })"
    Write-Host "  Candidate injection point: $(if ($asar.CandidateInjectionPointFound) { 'Found' } else { 'Missing' })"
    Write-Host "  ASAR integrity metadata: $(if ($asar.AsarIntegrityMetadataPresent) { 'Present' } else { 'Not found' })"
    if ($asar.Error) {
        Write-Host "  Inspection error: $($asar.Error)" -ForegroundColor Red
    }

    Write-Host "`nRenderer assets:" -ForegroundColor White
    $scripts = @($asar.RendererScripts | Select-Object -First 8)
    $styles = @($asar.RendererStyles | Select-Object -First 5)
    if ($scripts.Count -eq 0) { Write-Host "  Scripts: none found" -ForegroundColor Yellow }
    else { foreach ($script in $scripts) { Write-Host "  JS:  $script" } }
    if ($styles.Count -eq 0) { Write-Host "  Styles: none found" -ForegroundColor Yellow }
    else { foreach ($style in $styles) { Write-Host "  CSS: $style" } }

    Write-Host "`nHash embedding probe:" -ForegroundColor White
    try {
        $hashReport = Get-CodexHashEmbeddingReport -Inspection $inspection
        Write-Host "  ASAR header SHA256: $($hashReport.HeaderSha256)"
        Write-Host "  Full ASAR SHA256:   $($hashReport.FullAsarSha256)"
        foreach ($target in $hashReport.Targets) {
            if (-not $target.Exists) {
                Write-Host "  $($target.Name): missing"
            } else {
                Write-Host "  $($target.Name): header hash embedded=$($target.HeaderHashFound), full hash embedded=$($target.FullAsarHashFound)"
            }
        }
    } catch {
        Write-Host "  Hash probe failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`nRecommendation:" -ForegroundColor White
    Write-Host "  $(Get-CodexPhaseTwoRecommendation -Inspection $asar)" -ForegroundColor Cyan
}

