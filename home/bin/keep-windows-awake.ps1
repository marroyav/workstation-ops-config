param(
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $env:LOCALAPPDATA 'KeepWindowsAwake.pid'
$scriptName = Split-Path -Leaf $PSCommandPath

function Get-KeepWindowsAwakeProcess {
    param(
        [int]$ProcessId
    )

    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue

    if ($null -eq $candidate) {
        return $null
    }

    $isPowerShell = $candidate.Name -in @('powershell.exe', 'pwsh.exe')
    $isThisScript = -not [string]::IsNullOrWhiteSpace($candidate.CommandLine) -and
        $candidate.CommandLine.IndexOf($scriptName, [StringComparison]::OrdinalIgnoreCase) -ge 0

    if ($isPowerShell -and $isThisScript) {
        return $candidate
    }

    return $null
}

$savedPid = $null
if (Test-Path $pidFile) {
    try {
        $savedPid = [int](Get-Content $pidFile -Raw)
    }
    catch {
        # Treat an unreadable PID file as stale.
    }
}

$keepAwakeProcess = if ($null -ne $savedPid) {
    Get-KeepWindowsAwakeProcess -ProcessId $savedPid
}

if ($Stop) {
    if ($null -ne $keepAwakeProcess) {
        Stop-Process -Id $keepAwakeProcess.ProcessId -ErrorAction SilentlyContinue
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    exit 0
}

if ($null -ne $keepAwakeProcess) {
    exit 0
}

# Remove stale state before recording this process.
Remove-Item $pidFile -Force -ErrorAction SilentlyContinue

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class KeepAwakeNative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint executionState);
}
'@

$ES_CONTINUOUS       = [uint32]2147483648
$ES_SYSTEM_REQUIRED  = [uint32]0x00000001
$ES_DISPLAY_REQUIRED = [uint32]0x00000002
$keepAwakeState = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

Set-Content -Path $pidFile -Value $PID -NoNewline

try {
    if ([KeepAwakeNative]::SetThreadExecutionState($keepAwakeState) -eq 0) {
        throw 'Windows rejected the keep-awake request.'
    }

    while ($true) {
        Start-Sleep -Seconds 30
        [void][KeepAwakeNative]::SetThreadExecutionState($keepAwakeState)
    }
}
finally {
    [void][KeepAwakeNative]::SetThreadExecutionState($ES_CONTINUOUS)
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
