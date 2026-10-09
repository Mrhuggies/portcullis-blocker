# Installs the watchdog that keeps the block in place.
#
#   .\install-guard.ps1          (as Administrator)
#
# Windows has no equivalent of the file-watch macOS uses, so this checks every
# five minutes instead. One check costs a few milliseconds.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$DataDir  = "$env:ProgramData\Portcullis"
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = "Portcullis Guard"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This needs to run as Administrator." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "$DataDir\blocklist.hosts")) {
    Write-Host "Run .\install.ps1 first." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Copy-Item (Join-Path $Here "guard.ps1") "$DataDir\guard.ps1" -Force
Copy-Item (Join-Path $Here "lib.ps1")   "$DataDir\lib.ps1"   -Force
. (Join-Path $Here "lib.ps1")
Protect-PortcullisDir -Path $DataDir      # SYSTEM runs these, so only admins may change them

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DataDir\guard.ps1`""

$trigger = @(
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)),
    (New-ScheduledTaskTrigger -AtStartup)
)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description "Restores the Portcullis block list if it is removed." | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host "Guard installed." -ForegroundColor Green
Write-Host "  checks    : every 5 minutes"
Write-Host "  log       : $DataDir\guard.log"
Write-Host "  remove it : Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
