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
    Write-Host "  3. Exit"
}

function Invoke-SelectedAppAction {
    param([Parameter(Mandatory)][string]$ActionId)

    $invokeWithConfirmation = {
        param(
            [Parameter(Mandatory)][string]$Warning,
            [Parameter(Mandatory)][scriptblock]$Action
        )

        Write-Host ""
        Write-Host "Warning:" -ForegroundColor Yellow
        Write-Host $Warning -ForegroundColor Yellow
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
                -Warning "Patch will close and relaunch Codex if it is open.`nLaunch Codex using the Codex RTL shortcuts after patching." `
                -Action { Install-CodexRtlPatch }
        }
        'Restore' {
            & $invokeWithConfirmation `
                -Warning "Restore removes the RTL launcher and shortcuts created by this tool.`nIf Codex is still open, you may need to restart it afterward." `
                -Action { Restore-CodexRtlPatch }
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
            '3' { return }
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
