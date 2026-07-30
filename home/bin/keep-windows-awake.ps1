param(
    [ValidateRange(5, 3600)]
    [int]$PulseSeconds = 30
)

$source = @'
using System;
using System.Runtime.InteropServices;

public static class KeepAwakeNative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@

Add-Type -TypeDefinition $source

$ES_CONTINUOUS       = [uint32]2147483648
$ES_SYSTEM_REQUIRED  = [uint32]0x00000001
$ES_DISPLAY_REQUIRED = [uint32]0x00000002
$keepAwakeFlags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

Write-Host "Keeping Windows and the display awake. Press Ctrl+C to stop."

try {
    while ($true) {
        $result = [KeepAwakeNative]::SetThreadExecutionState($keepAwakeFlags)

        if ($result -eq 0) {
            throw "SetThreadExecutionState failed with Windows error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
        }

        Start-Sleep -Seconds $PulseSeconds
    }
}
finally {
    # Release the keep-awake request when the script exits.
    [void][KeepAwakeNative]::SetThreadExecutionState($ES_CONTINUOUS)
    Write-Host "Keep-awake request released."
}
