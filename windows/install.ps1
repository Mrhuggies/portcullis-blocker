# Portcullis for Windows - blocks adult sites system-wide.
#
#   Right-click this file > Run with PowerShell (as Administrator)
#   or, in an admin PowerShell:  .\install.ps1
#
# Two layers:
#   1. The hosts file, which every browser and app on Windows obeys.
#   2. Chrome and Edge policy, which those browsers cannot be talked out of.
#
# Everything it writes is reversible with uninstall.ps1, and your original
# hosts file is backed up first.
#
# UNTESTED: written carefully but not yet run on a real Windows machine.
# If something goes wrong, uninstall.ps1 restores the backup.

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$Begin    = "# >>> portcullis >>>"
$End      = "# <<< portcullis <<<"
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$DataDir  = "$env:ProgramData\Portcullis"
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here "lib.ps1")
$Root     = Split-Path -Parent $Here

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This needs to run as Administrator." -ForegroundColor Red
        Write-Host "Right-click the file and choose 'Run with PowerShell', or open PowerShell as Administrator."
        exit 1
    }
}

Assert-Admin

$blocklist = Join-Path $Root "blocklist.hosts"
$topList   = Join-Path $Root "top-domains.txt"
if (-not (Test-Path $blocklist)) { Write-Host "Missing blocklist.hosts next to this folder." -ForegroundColor Red; exit 1 }

Protect-PortcullisDir -Path $DataDir      # admin-only, since SYSTEM runs scripts from here

# ---------------------------------------------------------------- hosts file
Write-Host "Installing the block list..." -ForegroundColor Cyan

$stamp  = Get-Date -Format "yyyyMMddHHmmss"
$backup = "$DataDir\hosts.backup-$stamp"
Copy-Item $HostsPath $backup -Force
Write-Host "  backed up your hosts file to $backup"

Set-PortcullisBlock -Path $HostsPath -Payload @(Get-Content $blocklist)

Copy-Item $blocklist "$DataDir\blocklist.hosts" -Force
if (Test-Path $topList) { Copy-Item $topList "$DataDir\top-domains.txt" -Force }

$count = (Select-String -Path $HostsPath -Pattern '^0\.0\.0\.0 ' -AllMatches).Count
Write-Host "  $count sites blocked for every browser and app" -ForegroundColor Green

# ------------------------------------------------------- chrome / edge policy
Write-Host "Locking Chrome and Edge settings..." -ForegroundColor Cyan

$domains = @()
if (Test-Path $topList) { $domains = @(Get-Content $topList | Where-Object { $_ -match '\S' }) }
if ($domains.Count -gt 1000) { $domains = $domains[0..999] }   # policy caps at 1000

foreach ($browser in @(
    @{ Name = "Chrome"; Path = "HKLM:\SOFTWARE\Policies\Google\Chrome" },
    @{ Name = "Edge";   Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge" }
)) {
    $base = $browser.Path
    $list = "$base\URLBlocklist"
    New-Item -Path $list -Force | Out-Null
    Remove-ItemProperty -Path $list -Name * -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt $domains.Count; $i++) {
        New-ItemProperty -Path $list -Name ($i + 1) -Value $domains[$i] -PropertyType String -Force | Out-Null
    }

    # Stops the browser resolving names itself and skipping the hosts file.
    New-ItemProperty -Path $base -Name "DnsOverHttpsMode" -Value "off" -PropertyType String -Force | Out-Null

    Write-Host "  $($browser.Name): $($domains.Count) sites blocked, secure DNS turned off"
}

ipconfig /flushdns | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Close Chrome and Edge completely and reopen them, then try a blocked site to check."
Write-Host ""
Write-Host "Next, to stop the block being removed on a whim:" -ForegroundColor Cyan
Write-Host "  .\install-guard.ps1"
