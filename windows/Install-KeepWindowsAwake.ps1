[CmdletBinding()]
param(
    [switch]$KeepDisplayOn,
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$taskName = "WorkstationOps Keep Windows Awake"
$installDirectory = Join-Path $env:LOCALAPPDATA "WorkstationOps"
$installedScript = Join-Path $installDirectory "Keep-WindowsAwake.ps1"
$logPath = Join-Path $installDirectory "Keep-WindowsAwake.log"
$sourceScript = Join-Path $PSScriptRoot "Keep-WindowsAwake.ps1"

if ($Uninstall) {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    Remove-Item -LiteralPath $installedScript -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $installDirectory) {
        $remainingFiles = Get-ChildItem -LiteralPath $installDirectory -Force
        if ($remainingFiles.Count -eq 0) {
            Remove-Item -LiteralPath $installDirectory -Force
        }
    }

    Write-Output "Removed scheduled task '$taskName' and its deployed files."
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Runtime script not found: $sourceScript"
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force

$powerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$actionArguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScript`""
if ($KeepDisplayOn) {
    $actionArguments += " -KeepDisplayOn"
}

$userId = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $actionArguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -Hidden `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

$task = New-ScheduledTask `
    -Action $action `
    -Description "Prevents automatic Windows system sleep while this user is signed in." `
    -Principal $principal `
    -Settings $settings `
    -Trigger $trigger

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

$registeredTask = Get-ScheduledTask -TaskName $taskName
[pscustomobject]@{
    TaskName = $registeredTask.TaskName
    State = $registeredTask.State
    InstalledScript = $installedScript
    KeepDisplayOn = $KeepDisplayOn.IsPresent
}
