# Removes Portcullis from Windows - after a 48-hour wait.
#
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1           first run: files the request
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1           after 48h: removes it
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Cancel   calls it off
#
# (Windows blocks downloaded scripts by default; -ExecutionPolicy Bypass lets
# this one run without changing that setting for anything else.)
#
# The wait is the point. If one site is blocked by mistake, don't remove
# everything - see the guide for unblocking a single site.

#Requires -Version 5.1
param([switch]$Cancel)

$ErrorActionPreference = "Stop"

$Begin     = "# >>> portcullis >>>"
$End       = "# <<< portcullis <<<"
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$DataDir   = "$env:ProgramData\Portcullis"
$Request   = "$DataDir\removal-requested"
$TaskName  = "Portcullis Guard"
$WaitHours = 48

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "lib.ps1")

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This needs to run as Administrator." -ForegroundColor Red
    exit 1
}

if ($Cancel) {
    Remove-Item $Request -ErrorAction SilentlyContinue
    Write-Host "Removal cancelled. Everything stays as it is." -ForegroundColor Green
    exit 0
}

$lines = @(Get-Content $HostsPath -ErrorAction SilentlyContinue)
if (-not ($lines -contains $Begin)) {
    Write-Host "Nothing to remove - the block isn't installed."
    Remove-Item $Request -ErrorAction SilentlyContinue
    exit 0
}

# ------------------------------------------------- first run: file the request
if (-not (Test-Path $Request)) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    (Get-Date).ToString("o") | Set-Content $Request -Encoding utf8
    $ready = (Get-Date).AddHours($WaitHours)
    Write-Host ""
    Write-Host "Removal requested. Nothing has been removed yet." -ForegroundColor Yellow
    Write-Host "  Come back after $($ready.ToString('ddd dd MMM, HH:mm')) and run this again to confirm."
    Write-Host "  Changed your mind:  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Cancel"
    exit 0
}

# ------------------------------------------------------------- the second run
[datetime]$requested = Get-Date
$raw = (Get-Content $Request -Raw).Trim()
if (-not [datetime]::TryParse($raw, [ref]$requested)) { $requested = Get-Date }

$unlocks = $requested.AddHours($WaitHours)
if ((Get-Date) -lt $unlocks) {
    $left = $unlocks - (Get-Date)
    Write-Host ""
    Write-Host ("Not yet. {0}h {1}m left of the {2}-hour wait." -f `
        [int]$left.TotalHours, $left.Minutes, $WaitHours) -ForegroundColor Yellow
    Write-Host "  Requested : $($requested.ToString('ddd dd MMM, HH:mm'))"
    Write-Host "  Unlocks   : $($unlocks.ToString('ddd dd MMM, HH:mm'))"
    Write-Host "  Cancel    : powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Cancel"
    exit 1
}

# The guard would only put it straight back.
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$stamp = Get-Date -Format "yyyyMMddHHmmss"
Copy-Item $HostsPath "$DataDir\hosts.backup-$stamp" -Force

Write-HostsFile -Path $HostsPath -Lines (Remove-PortcullisBlock -Lines $lines)

foreach ($base in @("HKLM:\SOFTWARE\Policies\Google\Chrome", "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
    Remove-Item -Path "$base\URLBlocklist" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $base -Name "DnsOverHttpsMode" -Force -ErrorAction SilentlyContinue
}

Remove-Item $Request -ErrorAction SilentlyContinue
ipconfig /flushdns | Out-Null

Write-Host ""
Write-Host "Removed. The hosts file is back to how it was, and the browser policies are cleared." -ForegroundColor Green
Write-Host "Your original hosts file backups are in $DataDir if you need them."
