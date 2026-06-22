# MAIN MENU LOOP
# -----------------------------------------------------------------------------

function Write-MenuHeader {
    Clear-Host
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "                  Codex RTL Fix                       " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ActionMenu {
    param([Parameter(Mandatory)]$CodexApp)

    if ($CodexApp.Found) {
        Write-Host "Codex Desktop: Found" -ForegroundColor Green
    } else {
        Write-Host "Codex Desktop: Not found" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Select an action:" -ForegroundColor White
    Write-Host "  1. Patch Codex RTL"
    Write-Host "  2. Restore Codex RTL"
    Write-Host "  3. Inspect Codex Desktop"
    Write-Host "  4. Exit"
}

function Invoke-SelectedAppAction {
    param([Parameter(Mandatory)][string]$ActionId)

    $invokeWithConfirmation = {
        param(
            [Parameter(Mandatory)][string]$Warning,
            [Parameter(Mandatory)][scriptblock]$Action
        )

        Write-Host "`nWARNING: $Warning" -ForegroundColor Yellow
        if (-not (Read-YesNoPrompt -Prompt "Do you want to continue? (Y/n)")) {
            Write-Host "Operation cancelled."
            return
        }

        try {
            & $Action
        } catch {
            Write-Host "`n[!] Final Script Status:" -ForegroundColor DarkGray
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    switch ($ActionId) {
        'Patch' {
            & $invokeWithConfirmation `
                -Warning 'This will automatically close and relaunch Codex if it is currently open so it can start with local RTL injection support.' `
                -Action { Install-CodexRtlPatch }
        }
        'Restore' {
            & $invokeWithConfirmation `
                -Warning 'This will remove the Codex runtime RTL launcher and may require a Codex restart to fully clear injected state.' `
                -Action { Restore-CodexRtlPatch }
        }
        'Inspect' {
            Show-CodexInspection
        }
        default {
            Write-Warn "Unknown action: $ActionId"
        }
    }
}

function Show-Menu {
    $codexApp = @(Get-DetectedApps | Where-Object { $_.Name -eq 'Codex Desktop' } | Select-Object -First 1)
    if ($codexApp.Count -eq 0) {
        throw 'Codex Desktop detection is unavailable.'
    }

    while ($true) {
        Write-MenuHeader
        Write-ActionMenu -CodexApp $codexApp[0]
        $choice = (Read-Host "`nAction").Trim()

        switch ($choice) {
            '1' { Invoke-SelectedAppAction -ActionId 'Patch' }
            '2' { Invoke-SelectedAppAction -ActionId 'Restore' }
            '3' { Invoke-SelectedAppAction -ActionId 'Inspect' }
            '4' { return }
            default {
                Write-Warn "Unknown action: $choice"
                Start-Sleep -Seconds 2
                continue
            }
        }

        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
    }
}
