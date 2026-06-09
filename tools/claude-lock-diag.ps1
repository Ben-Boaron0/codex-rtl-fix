<#
.SYNOPSIS
    AI RTL Fix read-only Claude file-lock diagnostic.
.DESCRIPTION
    Collects process, service, path, ACL, open-mode, Restart Manager, and
    antivirus context for Claude Desktop patch lock failures. The script never
    writes to the Claude installation. Its only empirical write test runs on a
    temporary copy under the current user's TEMP directory.
#>

$ErrorActionPreference = 'Continue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ai-rtl-fix-claude-lock-diag.txt'
$sb = New-Object System.Text.StringBuilder

function Write-Line($Message) {
    [void]$sb.AppendLine([string]$Message)
    Write-Host $Message
}

function Write-Section($Title) {
    Write-Line ''
    Write-Line "==================== $Title ===================="
}

function Get-ErrorType($ErrorRecord) {
    if ($ErrorRecord.Exception.InnerException) { return $ErrorRecord.Exception.InnerException.GetType().Name }
    return $ErrorRecord.Exception.GetType().Name
}

function Get-ErrorMessage($ErrorRecord) {
    if ($ErrorRecord.Exception.InnerException) { return $ErrorRecord.Exception.InnerException.Message }
    return $ErrorRecord.Exception.Message
}

function Invoke-Safe($ScriptBlock) {
    try { & $ScriptBlock } catch { Write-Line "  [error] $(Get-ErrorType $_): $(Get-ErrorMessage $_)" }
}

function Find-ClaudeDirForDiag {
    $pkg = Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' -and $_.InstallLocation -like '*WindowsApps*' } | Select-Object -First 1
    if ($pkg) { return $pkg.InstallLocation }
    return $null
}

function Test-OpenMode($Path, [System.IO.FileAccess]$Access, [System.IO.FileShare]$Share) {
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, $Access, $Share)
        $fs.Close()
        return 'OK'
    } catch [System.UnauthorizedAccessException] {
        return "DENIED (UnauthorizedAccessException): $($_.Exception.Message)"
    } catch [System.IO.IOException] {
        return "LOCKED (IOException): $($_.Exception.Message)"
    } catch {
        return "OTHER ($($_.Exception.GetType().Name)): $($_.Exception.Message)"
    }
}

$script:RmReady = $false
function Initialize-RestartManagerType {
    if ($script:RmReady) { return $true }
    try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class AiRtlFixRmLock {
    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }
    const int CCH_RM_MAX_APP_NAME = 255;
    const int CCH_RM_MAX_SVC_NAME = 63;
    enum RM_APP_TYPE { RmUnknownApp=0, RmMainWindow=1, RmOtherWindow=2, RmService=3, RmExplorer=4, RmConsole=5, RmCritical=1000 }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)] public string strServiceShortName;
        public RM_APP_TYPE ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, [In] RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);
    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
    public static List<string> GetLockers(string path) {
        var result = new List<string>();
        uint handle; string key = Guid.NewGuid().ToString();
        int res = RmStartSession(out handle, 0, key);
        if (res != 0) throw new Exception("RmStartSession failed: " + res);
        try {
            string[] resources = new string[] { path };
            res = RmRegisterResources(handle, (uint)resources.Length, resources, 0, null, 0, null);
            if (res != 0) throw new Exception("RmRegisterResources failed: " + res);
            uint needed = 0, count = 0, reason = 0;
            res = RmGetList(handle, out needed, ref count, null, ref reason);
            if (res == 234) {
                var info = new RM_PROCESS_INFO[needed];
                count = needed;
                res = RmGetList(handle, out needed, ref count, info, ref reason);
                if (res != 0) throw new Exception("RmGetList(2) failed: " + res);
                for (int i = 0; i < count; i++)
                    result.Add(info[i].strAppName + " (PID " + info[i].Process.dwProcessId + ", type " + info[i].ApplicationType + ")");
            } else if (res != 0) {
                throw new Exception("RmGetList(1) failed: " + res);
            }
        } finally { RmEndSession(handle); }
        return result;
    }
}
'@
        $script:RmReady = $true
        return $true
    } catch {
        if ("$($_.Exception.Message)" -match 'already') { $script:RmReady = $true; return $true }
        Write-Line "  Restart Manager unavailable: $($_.Exception.Message)"
        return $false
    }
}

Write-Line "AI RTL Fix Claude file-lock diagnostic - $(Get-Date -Format o) (read-only)"

Write-Section '1. Context'
Invoke-Safe {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    Write-Line "User            : $($id.Name)"
    Write-Line "Elevated (admin): $admin"
    Write-Line "OS              : $((Get-CimInstance Win32_OperatingSystem).Caption)"
    Write-Line "OS Build        : $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
    Write-Line "PowerShell      : $($PSVersionTable.PSVersion)"
    Write-Line ".NET (CLR)      : $([System.Environment]::Version)"
}

Write-Section '2. Claude Processes And Service'
Invoke-Safe {
    foreach ($name in @('claude', 'cowork-svc')) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            $procs | ForEach-Object { Write-Line "  RUNNING: $name PID=$($_.Id) Path=$($_.Path)" }
        } else {
            Write-Line "  not running: $name"
        }
    }
}
Invoke-Safe {
    $svc = Get-WmiObject Win32_Service | Where-Object { $_.PathName -match 'cowork-svc' }
    if ($svc) { Write-Line "  Service: $($svc.Name) State=$($svc.State) StartMode=$($svc.StartMode) Path=$($svc.PathName)" }
    else { Write-Line '  No cowork-svc Windows service found.' }
}

Write-Section '3. Claude Install Paths'
$ClaudeDir = Find-ClaudeDirForDiag
$AppDir = if ($ClaudeDir) { Join-Path $ClaudeDir 'app' } else { $null }
$ResourcesDir = if ($AppDir) { Join-Path $AppDir 'resources' } else { $null }
$ExePath = if ($AppDir) { Join-Path $AppDir 'claude.exe' } else { $null }
$CoworkSvcPath = if ($ResourcesDir) { Join-Path $ResourcesDir 'cowork-svc.exe' } else { $null }
$AsarPath = if ($ResourcesDir) { Join-Path $ResourcesDir 'app.asar' } else { $null }
Write-Line "  ClaudeDir     : $ClaudeDir"
Write-Line "  AppDir        : $AppDir"
Write-Line "  ExePath       : $ExePath"
Write-Line "  CoworkSvcPath : $CoworkSvcPath"
Write-Line "  AsarPath      : $AsarPath"
if (-not $ClaudeDir) {
    $legacy = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $legacy) { Write-Line "  Legacy Squirrel install detected: $legacy" }
}

$Targets = @($ExePath, $CoworkSvcPath, $AsarPath) | Where-Object { $_ }

Write-Section '4. File Attributes, Owner, ACL'
foreach ($target in $Targets) {
    Write-Line ''
    Write-Line "-- $(Split-Path $target -Leaf) --"
    if (-not (Test-Path -LiteralPath $target)) { Write-Line "  MISSING: $target"; continue }
    Invoke-Safe {
        $item = Get-Item -LiteralPath $target -Force
        Write-Line "  Size       : $($item.Length) bytes"
        Write-Line "  Attributes : $($item.Attributes)"
        Write-Line "  ReadOnly   : $([bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly))"
    }
    Invoke-Safe {
        $acl = Get-Acl -LiteralPath $target
        Write-Line "  Owner      : $($acl.Owner)"
        Write-Line '  Access     :'
        foreach ($ace in $acl.Access) {
            Write-Line ("     {0,-32} {1,-10} {2}" -f $ace.IdentityReference, $ace.AccessControlType, $ace.FileSystemRights)
        }
    }
}

Write-Section '5. Non-Destructive Open Matrix'
$matrix = @(
    @{ Access = [System.IO.FileAccess]::Read;  Share = [System.IO.FileShare]::Read; Label = '(Open, Read,  Read)' },
    @{ Access = [System.IO.FileAccess]::Write; Share = [System.IO.FileShare]::Read; Label = '(Open, Write, Read)  patch write probe' },
    @{ Access = [System.IO.FileAccess]::ReadWrite; Share = [System.IO.FileShare]::None; Label = '(Open, ReadWrite, None) legacy strict probe' }
)
foreach ($target in $Targets) {
    Write-Line ''
    Write-Line "-- $(Split-Path $target -Leaf) --"
    if (-not (Test-Path -LiteralPath $target)) { Write-Line '  MISSING'; continue }
    foreach ($mode in $matrix) {
        Write-Line ("  {0,-46} : {1}" -f $mode.Label, (Test-OpenMode $target $mode.Access $mode.Share))
    }
}

Write-Section '6. Empirical WriteAllBytes Test On TEMP Copy'
if ($ExePath -and (Test-Path -LiteralPath $ExePath)) {
    Invoke-Safe {
        $tmp = Join-Path $env:TEMP ("ai-rtl-fix-lock-diag-" + [guid]::NewGuid().ToString('N') + '.bin')
        Copy-Item -LiteralPath $ExePath -Destination $tmp -Force
        try {
            $bytes = [System.IO.File]::ReadAllBytes($tmp)
            $shareRW = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $holderA = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $shareRW)
            try {
                try { [System.IO.File]::WriteAllBytes($tmp, $bytes); $resultA = 'SUCCESS' }
                catch { $resultA = "FAILED ($(Get-ErrorType $_)): $(Get-ErrorMessage $_)" }
            } finally { $holderA.Close() }
            Write-Line "  Read holder sharing ReadWrite/Delete + WriteAllBytes: $resultA"

            $holderB = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                try { [System.IO.File]::WriteAllBytes($tmp, $bytes); $resultB = 'SUCCESS' }
                catch { $resultB = "FAILED ($(Get-ErrorType $_)): $(Get-ErrorMessage $_)" }
            } finally { $holderB.Close() }
            Write-Line "  Read holder sharing Read only + WriteAllBytes       : $resultB"
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Line '  skipped: claude.exe not found.'
}

Write-Section '7. Restart Manager Holders'
if (Initialize-RestartManagerType) {
    foreach ($target in $Targets) {
        if (-not (Test-Path -LiteralPath $target)) { continue }
        Invoke-Safe {
            $lockers = [AiRtlFixRmLock]::GetLockers($target)
            if ($lockers.Count -eq 0) {
                Write-Line "  $(Split-Path $target -Leaf): no holders reported"
            } else {
                Write-Line "  $(Split-Path $target -Leaf): held by:"
                $lockers | ForEach-Object { Write-Line "      $_" }
            }
        }
    }
}

Write-Section '8. Antivirus Context'
Invoke-Safe {
    $status = Get-MpComputerStatus -ErrorAction Stop
    Write-Line "  RealTimeProtectionEnabled : $($status.RealTimeProtectionEnabled)"
    Write-Line "  AntivirusEnabled          : $($status.AntivirusEnabled)"
    Write-Line "  AMRunningMode             : $($status.AMRunningMode)"
}
Invoke-Safe {
    $products = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
    if ($products) {
        Write-Line '  Registered AV products:'
        $products | ForEach-Object { Write-Line "      $($_.displayName)" }
    }
}

Write-Section '9. AppX Package'
Invoke-Safe {
    $pkg = Get-AppxPackage *Claude* | Select-Object -First 1
    if ($pkg) {
        Write-Line "  Name            : $($pkg.Name)"
        Write-Line "  Version         : $($pkg.Version)"
        Write-Line "  PackageFullName : $($pkg.PackageFullName)"
        Write-Line "  InstallLocation : $($pkg.InstallLocation)"
        Write-Line "  Status          : $($pkg.Status)"
        Write-Line "  SignatureKind   : $($pkg.SignatureKind)"
    } else {
        Write-Line '  No *Claude* AppX package found.'
    }
}

[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ''
Write-Host '==================================================================' -ForegroundColor Green
Write-Host "Done. Report saved to: $out" -ForegroundColor Green
Write-Host 'Review the report for file holders, ACL denial, or antivirus context.' -ForegroundColor Gray
