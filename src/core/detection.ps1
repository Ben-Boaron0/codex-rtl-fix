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
        Get-AppDetectionStatus -Name 'Claude Desktop' -InstallLocation (Find-ClaudeDir) -SupportStatus 'Supported'
        Get-AppDetectionStatus -Name 'Codex Desktop' -InstallLocation (Find-CodexDir) -SupportStatus 'Planned'
        Get-AppDetectionStatus -Name 'ChatGPT Desktop' -InstallLocation $null -SupportStatus 'Planned'
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

