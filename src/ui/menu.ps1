# MAIN MENU LOOP
# -----------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                   AI RTL Fix                    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Show-DetectedApps -Apps (Get-DetectedApps)
    Write-Host "`nSelect an action:"
    Write-Host "  1. Patch Claude Desktop RTL" -ForegroundColor White
    Write-Host "  2. Restore Claude Desktop" -ForegroundColor White
    Write-Host "  3. Create Claude quick update shortcut" -ForegroundColor Green
    Write-Host "  4. Enable Claude auto re-patch" -ForegroundColor Green
    Write-Host "  5. Disable Claude auto re-patch" -ForegroundColor White
    Write-Host "  6. Inspect Codex Desktop" -ForegroundColor White
    Write-Host "  7. Exit" -ForegroundColor White

    $choice = Read-Host "`nEnter your choice (1/2/3/4/5/6/7)"

    if ($choice -eq '1' -or $choice -eq '2') {
        Write-Host "`nWARNING: This will automatically close Claude Desktop and its background services." -ForegroundColor Yellow
        $confirm = Read-Host "Do you want to continue? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Host "Operation cancelled."
            Start-Sleep -Seconds 2
            Show-Menu
            return
        }

        try {
            if ($choice -eq '1') { Install-Patch }
            else { Restore-Patch }
        } catch {
            Write-Host "`n[!] Final Script Status:" -ForegroundColor DarkGray
            Write-Host $_.Exception.Message -ForegroundColor Red
        }

        Write-Host "`nPress Enter to exit..."
        $null = Read-Host
    }
    elseif ($choice -eq '3') {
        Create-UpdateShortcut
        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
        Show-Menu
    }
    elseif ($choice -eq '4') {
        try { Install-AutoUpdateTask } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
        Show-Menu
    }
    elseif ($choice -eq '5') {
        try { Uninstall-AutoUpdateTask } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
        Show-Menu
    }
    elseif ($choice -eq '6') {
        Show-CodexInspection
        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
        Show-Menu
    }
    elseif ($choice -eq '7') { Exit }
    else { Show-Menu }
}

