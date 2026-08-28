[CmdletBinding()]
param(
    [switch]$AllowDisplaySleep,

    [ValidateRange(15, 3600)]
    [int]$RefreshSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

$installDirectory = Join-Path $env:LOCALAPPDATA "WorkstationOps"
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
$logPath = Join-Path $installDirectory "Keep-WindowsAwake.log"
$keepDisplayOn = -not $AllowDisplaySleep.IsPresent

function Write-AwakeLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    Add-Content -LiteralPath $logPath -Value "$timestamp $Message"
}

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
    Write-AwakeLog "stopped pid=$PID"
}
