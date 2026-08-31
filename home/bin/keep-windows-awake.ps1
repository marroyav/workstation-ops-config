[CmdletBinding()]
param(
    [switch]$AllowDisplaySleep,

    [ValidateRange(15, 3600)]
    [int]$RefreshSeconds = 60,

    [switch]$Stop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installDirectory = Join-Path $env:LOCALAPPDATA "WorkstationOps"
$logPath = Join-Path $installDirectory "Keep-WindowsAwake.log"
$pidPath = Join-Path $installDirectory "Keep-WindowsAwake.pid"
$scriptName = Split-Path -Leaf $PSCommandPath

function Get-KeepWindowsAwakeProcess {
    param(
        [int]$ProcessId
    )

    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue

    if ($null -eq $candidate) {
        return $null
    }

    $isPowerShell = $candidate.Name -in @("powershell.exe", "pwsh.exe")
    $isThisScript = -not [string]::IsNullOrWhiteSpace($candidate.CommandLine) -and
        $candidate.CommandLine.IndexOf($scriptName, [StringComparison]::OrdinalIgnoreCase) -ge 0

    if ($isPowerShell -and $isThisScript) {
        return $candidate
    }

    return $null
}

function Get-SavedProcessId {
    if (-not (Test-Path -LiteralPath $pidPath)) {
        return $null
    }

    try {
        return [int](Get-Content -LiteralPath $pidPath -Raw)
    }
    catch {
        return $null
    }
}

function Remove-OwnedPidFile {
    if ((Get-SavedProcessId) -eq $PID) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
}

$savedPid = Get-SavedProcessId
$keepAwakeProcess = if ($null -ne $savedPid) {
    Get-KeepWindowsAwakeProcess -ProcessId $savedPid
}

if ($Stop) {
    if ($null -ne $keepAwakeProcess) {
        Stop-Process -Id $keepAwakeProcess.ProcessId -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    exit 0
}

if ($null -ne $keepAwakeProcess) {
    exit 0
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue

$nativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WorkstationOps
{
    public static class Awake
    {
        private const uint EsSystemRequired = 0x00000001;
        private const uint EsDisplayRequired = 0x00000002;
        private const uint EsContinuous = 0x80000000;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SetThreadExecutionState(uint executionState);

        public static void Enable(bool keepDisplayOn)
        {
            uint state = EsContinuous | EsSystemRequired;
            if (keepDisplayOn)
            {
                state |= EsDisplayRequired;
            }

            if (SetThreadExecutionState(state) == 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }

        public static void Clear()
        {
            SetThreadExecutionState(EsContinuous);
        }
    }
}
'@

Add-Type -TypeDefinition $nativeSource -Language CSharp

$keepDisplayOn = -not $AllowDisplaySleep.IsPresent

function Write-AwakeLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    Add-Content -LiteralPath $logPath -Value "$timestamp $Message"
}

Set-Content -LiteralPath $pidPath -Value $PID -NoNewline

try {
    Write-AwakeLog "started pid=$PID keepDisplayOn=$keepDisplayOn refreshSeconds=$RefreshSeconds"

    while ($true) {
        [WorkstationOps.Awake]::Enable($keepDisplayOn)
        Start-Sleep -Seconds $RefreshSeconds
    }
}
catch {
    Write-AwakeLog "failed: $($_.Exception.Message)"
    throw
}
finally {
    [WorkstationOps.Awake]::Clear()
    Remove-OwnedPidFile
    Write-AwakeLog "stopped pid=$PID"
}
