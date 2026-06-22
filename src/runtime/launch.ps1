function Get-CodexRtlDefaultPort {
    18317
}

function Test-TcpPortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Get-CodexRtlAvailablePort {
    $start = Get-CodexRtlDefaultPort
    for ($port = $start; $port -lt ($start + 50); $port++) {
        if (Test-TcpPortAvailable -Port $port) { return $port }
    }
    return $start
}

function New-CodexRtlLaunchArguments {
    param([Parameter(Mandatory)][int]$Port)

    @(
        "--remote-debugging-port=$Port",
        '--remote-debugging-address=127.0.0.1'
    )
}

function Test-CodexProcessHasRtlDebugPort {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][int]$Port
    )

    return [bool]($Process.CommandLine -match [regex]::Escape("--remote-debugging-port=$Port") -and
        $Process.CommandLine -match [regex]::Escape('--remote-debugging-address=127.0.0.1'))
}

function Get-CodexDesktopProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'Codex.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*' }
}

function Stop-CodexDesktopProcesses {
    foreach ($process in @(Get-CodexDesktopProcesses)) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "Could not stop Codex process $($process.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Start-CodexWithRtlDebug {
    param(
        [Parameter(Mandatory)][string]$AppExe,
        [Parameter(Mandatory)][int]$Port
    )

    Start-Process `
        -FilePath $AppExe `
        -ArgumentList (New-CodexRtlLaunchArguments -Port $Port) `
        -WorkingDirectory (Get-CodexRtlWorkingDirectory) | Out-Null
}

function Start-CodexNormally {
    param([Parameter(Mandatory)][string]$AppExe)

    Start-Process `
        -FilePath $AppExe `
        -WorkingDirectory (Split-Path -Parent $AppExe) | Out-Null
}

function Start-CodexForRtl {
    param(
        [Parameter(Mandatory)]$Inspection,
        [Parameter(Mandatory)][int]$Port,
        [switch]$AllowRestart
    )

    $processes = @(Get-CodexDesktopProcesses)
    if ($processes.Count -eq 0) {
        Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
        return 'started'
    }

    if (@($processes | Where-Object { Test-CodexProcessHasRtlDebugPort -Process $_ -Port $Port }).Count -gt 0) {
        return 'already-running'
    }

    if ($AllowRestart) {
        Write-Host 'Restarting Codex with local RTL injection support...' -ForegroundColor Yellow
        Stop-CodexDesktopProcesses
        Start-Sleep -Milliseconds 700
        Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
        return 'restarted'
    }

    return 'running-without-debug-port'
}

function Test-CodexDevToolsTarget {
    param([Parameter(Mandatory)]$Target)

    if ($Target.type -ne 'page') { return $false }
    if (-not $Target.webSocketDebuggerUrl) { return $false }

    $url = [string]$Target.url
    return ($url -like 'app://*')
}

function Get-CodexDevToolsTargets {
    param([Parameter(Mandatory)][int]$Port)

    $uri = "http://127.0.0.1:$Port/json/list"
    try {
        return @(Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 2)
    } catch {
        return @()
    }
}

function Wait-CodexDevToolsTargets {
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $targets = @(Get-CodexDevToolsTargets -Port $Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
        if ($targets.Count -gt 0) { return $targets }
        Start-Sleep -Milliseconds 500
    }
    return @()
}

function New-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{}
    )

    [pscustomobject]@{
        id = $Id
        method = $Method
        params = [pscustomobject]$Params
    }
}

function Invoke-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][string]$WebSocketDebuggerUrl,
        [Parameter(Mandatory)]$Command
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $buffer = New-Object byte[] 65536
    try {
        $client.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $json = $Command | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $segment = [ArraySegment[byte]]::new($bytes)
        $client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $receive = [ArraySegment[byte]]::new($buffer)
        $message = [System.Collections.Generic.List[byte]]::new()
        $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw 'Codex DevTools closed the WebSocket before returning a response.'
        }
        if ($result.Count -gt 0) {
            $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
        }
        while (-not $result.EndOfMessage) {
            $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'Codex DevTools closed the WebSocket before returning a complete response.'
            }
            if ($result.Count -gt 0) {
                $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
            }
        }
        return [System.Text.Encoding]::UTF8.GetString($message.ToArray())
    } finally {
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        }
        $client.Dispose()
    }
}

function Invoke-CodexRtlInjectionForTarget {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$Payload
    )

    $commands = @(
        (New-CodexCdpCommand -Id 1 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{
            source = $Payload
            runImmediately = $true
        }),
        (New-CodexCdpCommand -Id 2 -Method 'Runtime.evaluate' -Params @{
            expression = $Payload
            awaitPromise = $true
            returnByValue = $true
        })
    )

    foreach ($command in $commands) {
        Invoke-CodexCdpCommand -WebSocketDebuggerUrl $Target.webSocketDebuggerUrl -Command $command | Out-Null
    }
}

function Invoke-CodexRtlInjection {
    param([Parameter(Mandatory)][int]$Port)

    $payload = Get-CodexRtlPayload
    $targets = @(Wait-CodexDevToolsTargets -Port $Port)
    if ($targets.Count -eq 0) {
        Write-Warn "Codex DevTools target was not found on port $Port."
        return $false
    }

    foreach ($target in $targets) {
        try {
            Invoke-CodexRtlInjectionForTarget -Target $target -Payload $payload
        } catch {
            Write-Warn "Codex RTL injection failed for target '$($target.title)': $($_.Exception.Message)"
        }
    }
    return $true
}
