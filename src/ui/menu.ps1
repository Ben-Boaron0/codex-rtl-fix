# MAIN MENU LOOP
# -----------------------------------------------------------------------------

function Get-AppMenuId {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -like 'Claude*') { return 'claude' }
    if ($Name -like 'Codex*') { return 'codex' }
    if ($Name -like 'ChatGPT*') { return 'chatgpt' }
    return ($Name -replace '\s+', '-').ToLowerInvariant()
}

function Get-AppMenuCapabilities {
    param([Parameter(Mandatory)]$App)

    if (-not $App.Found) { return @() }
    switch ($App.Id) {
        'claude' {
            if ($App.SupportStatus -eq 'Supported') {
                return @('Patch', 'Restore', 'QuickUpdate', 'EnableAuto', 'DisableAuto')
            }
            return @()
        }
        'codex' { return @('Inspect') }
        default { return @() }
    }
}

function Test-AppMenuSelectable {
    param([Parameter(Mandatory)]$App)
    return (@(Get-AppMenuCapabilities -App $App).Count -gt 0)
}

function New-AppMenuState {
    $index = 0
    foreach ($app in (Get-DetectedApps)) {
        $index++
        $menuApp = [pscustomobject]@{
            Index = $index
            Id = Get-AppMenuId -Name $app.Name
            Name = $app.Name
            InstallLocation = $app.InstallLocation
            Found = $app.Found
            SupportStatus = $app.SupportStatus
            Selected = $false
            Selectable = $false
        }
        $menuApp.Selectable = Test-AppMenuSelectable -App $menuApp
        $menuApp
    }
}

function Get-MenuActionDefinitions {
    @(
        [pscustomobject]@{ Id = 'Patch';       Label = 'Patch selected apps';                  Capabilities = @('Patch') }
        [pscustomobject]@{ Id = 'Restore';     Label = 'Restore selected apps';                Capabilities = @('Restore') }
        [pscustomobject]@{ Id = 'Inspect';     Label = 'Inspect selected apps';                Capabilities = @('Inspect') }
        [pscustomobject]@{ Id = 'QuickUpdate'; Label = 'Create Claude quick update shortcut';  Capabilities = @('QuickUpdate') }
        [pscustomobject]@{ Id = 'EnableAuto';  Label = 'Enable Claude auto re-patch';          Capabilities = @('EnableAuto') }
        [pscustomobject]@{ Id = 'DisableAuto'; Label = 'Disable Claude auto re-patch';         Capabilities = @('DisableAuto') }
    )
}

function Get-AvailableMenuActions {
    param([Parameter(Mandatory)][object[]]$SelectedApps)

    $selectedCapabilities = @($SelectedApps | ForEach-Object { Get-AppMenuCapabilities -App $_ } | Select-Object -Unique)
    foreach ($action in (Get-MenuActionDefinitions)) {
        if (@($action.Capabilities | Where-Object { $selectedCapabilities -contains $_ }).Count -gt 0) {
            $action
        }
    }
}

function Write-MenuHeader {
    Clear-Host
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "                    AI RTL Fix                        " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-AppSelectionMenu {
    param([Parameter(Mandatory)][object[]]$Apps)

    Write-Host "Select target apps:" -ForegroundColor White
    foreach ($app in $Apps) {
        $mark = if ($app.Selected) { '[x]' } else { '[ ]' }
        if ($app.Found -and $app.Selectable) {
            Write-Host ("  {0}. {1} {2}: Found" -f $app.Index, $mark, $app.Name) -ForegroundColor Green
        } elseif ($app.Found) {
            Write-Host ("  {0}. {1} {2}: Found ({3})" -f $app.Index, $mark, $app.Name, $app.SupportStatus.ToLowerInvariant()) -ForegroundColor Yellow
        } else {
            Write-Host ("  {0}. {1} {2}: Not found ({3})" -f $app.Index, $mark, $app.Name, $app.SupportStatus.ToLowerInvariant()) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "Toggle app number, A for all supported, C to continue, Q to exit" -ForegroundColor White
}

function Select-MenuApps {
    $apps = @(New-AppMenuState)
    while ($true) {
        Write-MenuHeader
        Write-AppSelectionMenu -Apps $apps
        $choice = (Read-Host "`nSelection").Trim()

        if ($choice -eq 'Q' -or $choice -eq 'q') { return $null }
        if ($choice -eq 'A' -or $choice -eq 'a') {
            foreach ($app in $apps) {
                $app.Selected = [bool]$app.Selectable
            }
            continue
        }
        if ($choice -eq 'C' -or $choice -eq 'c') {
            $selected = @($apps | Where-Object { $_.Selected })
            if ($selected.Count -gt 0) { return $selected }
            Write-Warn "Select at least one supported app before continuing."
            Start-Sleep -Seconds 2
            continue
        }
        if ($choice -match '^\d+$') {
            $selectedApp = @($apps | Where-Object { $_.Index -eq [int]$choice } | Select-Object -First 1)
            if ($selectedApp.Count -eq 0) {
                Write-Warn "Unknown app selection: $choice"
                Start-Sleep -Seconds 2
                continue
            }
            if (-not $selectedApp[0].Selectable) {
                Write-Warn "$($selectedApp[0].Name) is not supported for actions yet."
                Start-Sleep -Seconds 2
                continue
            }
            $selectedApp[0].Selected = -not $selectedApp[0].Selected
            continue
        }

        Write-Warn "Unknown selection: $choice"
        Start-Sleep -Seconds 2
    }
}

function Write-ActionMenu {
    param(
        [Parameter(Mandatory)][object[]]$SelectedApps,
        [Parameter(Mandatory)][object[]]$Actions
    )

    Write-Host "Selected apps:" -ForegroundColor White
    foreach ($app in $SelectedApps) {
        Write-Host "  - $($app.Name)"
    }

    Write-Host "`nSelect an action:" -ForegroundColor White
    for ($i = 0; $i -lt $Actions.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Actions[$i].Label) -ForegroundColor White
    }
    Write-Host "  B. Back to app selection" -ForegroundColor White
    Write-Host "  Q. Exit" -ForegroundColor White
}

function Select-MenuAction {
    param([Parameter(Mandatory)][object[]]$SelectedApps)

    $actions = @(Get-AvailableMenuActions -SelectedApps $SelectedApps)
    while ($true) {
        Write-MenuHeader
        Write-ActionMenu -SelectedApps $SelectedApps -Actions $actions
        $choice = (Read-Host "`nAction").Trim()

        if ($choice -eq 'Q' -or $choice -eq 'q') { return 'Exit' }
        if ($choice -eq 'B' -or $choice -eq 'b') { return $null }
        if ($choice -match '^\d+$') {
            $index = [int]$choice
            if ($index -ge 1 -and $index -le $actions.Count) {
                return $actions[$index - 1].Id
            }
        }

        Write-Warn "Unknown action: $choice"
        Start-Sleep -Seconds 2
    }
}

function Invoke-SelectedAppAction {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][object[]]$SelectedApps
    )

    $selectedById = @{}
    foreach ($app in $SelectedApps) { $selectedById[$app.Id] = $app }

    switch ($ActionId) {
        'Patch' {
            if ($selectedById.ContainsKey('claude')) {
                Write-Host "`nWARNING: This will automatically close Claude Desktop and its background services." -ForegroundColor Yellow
                $confirm = Read-Host "Do you want to continue? (Y/n)"
                if ($confirm -eq 'n' -or $confirm -eq 'N') {
                    Write-Host "Operation cancelled."
                } else {
                    try { Install-Patch } catch {
                        Write-Host "`n[!] Final Script Status:" -ForegroundColor DarkGray
                        Write-Host $_.Exception.Message -ForegroundColor Red
                    }
                }
            }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'claude' }) {
                Write-Warn "$($app.Name) skipped: patch not supported yet."
            }
        }
        'Restore' {
            if ($selectedById.ContainsKey('claude')) {
                Write-Host "`nWARNING: This will automatically close Claude Desktop and its background services." -ForegroundColor Yellow
                $confirm = Read-Host "Do you want to continue? (Y/n)"
                if ($confirm -eq 'n' -or $confirm -eq 'N') {
                    Write-Host "Operation cancelled."
                } else {
                    try { Restore-Patch } catch {
                        Write-Host "`n[!] Final Script Status:" -ForegroundColor DarkGray
                        Write-Host $_.Exception.Message -ForegroundColor Red
                    }
                }
            }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'claude' }) {
                Write-Warn "$($app.Name) skipped: restore not supported yet."
            }
        }
        'Inspect' {
            if ($selectedById.ContainsKey('codex')) { Show-CodexInspection }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'codex' }) {
                Write-Warn "$($app.Name) skipped: inspect not supported yet."
            }
        }
        'QuickUpdate' {
            if ($selectedById.ContainsKey('claude')) { Create-UpdateShortcut }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'claude' }) {
                Write-Warn "$($app.Name) skipped: quick update shortcut not supported yet."
            }
        }
        'EnableAuto' {
            if ($selectedById.ContainsKey('claude')) {
                try { Install-AutoUpdateTask } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'claude' }) {
                Write-Warn "$($app.Name) skipped: auto re-patch not supported yet."
            }
        }
        'DisableAuto' {
            if ($selectedById.ContainsKey('claude')) {
                try { Uninstall-AutoUpdateTask } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
            foreach ($app in $SelectedApps | Where-Object { $_.Id -ne 'claude' }) {
                Write-Warn "$($app.Name) skipped: auto re-patch not supported yet."
            }
        }
        default {
            Write-Warn "Unknown action: $ActionId"
        }
    }
}

function Show-Menu {
    while ($true) {
        $selectedApps = Select-MenuApps
        if ($null -eq $selectedApps) { return }

        $action = Select-MenuAction -SelectedApps $selectedApps
        if ($action -eq 'Exit') { return }
        if ($null -eq $action) { continue }

        Invoke-SelectedAppAction -ActionId $action -SelectedApps $selectedApps

        Write-Host "`nPress Enter to return to menu..."
        $null = Read-Host
    }
}
