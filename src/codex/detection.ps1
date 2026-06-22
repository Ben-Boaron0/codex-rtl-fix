function Find-CodexDir {
    $pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) { return $pkg.InstallLocation }
    return $null
}

function Get-CodexInstallInfo {
    $pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    $installLocation = if ($pkg) { $pkg.InstallLocation } else { $null }
    $appDir = if ($installLocation) { Join-Path $installLocation 'app' } else { $null }
    $appExe = if ($appDir) { Join-Path $appDir 'Codex.exe' } else { $null }

    [pscustomobject]@{
        PackageFound = [bool]$pkg
        PackageName = if ($pkg) { $pkg.Name } else { $null }
        PackageVersion = if ($pkg) { $pkg.Version.ToString() } else { $null }
        InstallLocation = $installLocation
        AppExe = $appExe
    }
}

function Get-AppDetectionStatus {
    param(
        [string]$Name,
        [string]$InstallLocation,
        [string]$SupportStatus
    )

    [pscustomobject]@{
        Name = $Name
        InstallLocation = $InstallLocation
        Found = [bool]$InstallLocation
        SupportStatus = $SupportStatus
    }
}

function Get-DetectedApps {
    @(
        Get-AppDetectionStatus -Name 'Codex Desktop' -InstallLocation (Find-CodexDir) -SupportStatus 'Supported'
    )
}

function Show-DetectedApps {
    param([object[]]$Apps)

    Write-Host "Detected apps:" -ForegroundColor White
    foreach ($app in $Apps) {
        if ($app.Found -and $app.SupportStatus -eq 'Supported') {
            Write-Host ("  {0}: Found" -f $app.Name) -ForegroundColor Green
        } elseif ($app.Found) {
            Write-Host ("  {0}: Found ({1})" -f $app.Name, $app.SupportStatus.ToLowerInvariant()) -ForegroundColor Yellow
        } else {
            Write-Host ("  {0}: Not found ({1})" -f $app.Name, $app.SupportStatus.ToLowerInvariant()) -ForegroundColor DarkGray
        }
    }
}
