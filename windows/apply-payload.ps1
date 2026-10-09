# Writes a prepared block into the Windows hosts file. The panel runs this
# through the Windows permission (UAC) prompt, so it runs as Administrator.
#
#   apply-payload.ps1 -Payload FILE -Resources DIR -Result FILE
#   apply-payload.ps1 -Payload FILE -Check           validate only, no admin needed
#
# The payload comes from a process running as an ordinary user, so nothing in
# it is trusted: it's read into memory once, checked line by line, and refused
# unless every entry is "0.0.0.0 <hostname>". That's what stops this script -
# running with full rights - from ever being used to redirect a real site.

#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$Payload,
    [string]$Resources,
    [string]$Result,
    [switch]$Check
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "lib.ps1")

$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$DataDir   = "$env:ProgramData\Portcullis"
$TaskName  = "Portcullis Guard"

function Finish($ok, $message, $code) {
    if ($Result) {
        $json = @{ ok = $ok; message = $message } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($Result, $json, (New-Object System.Text.UTF8Encoding($false)))
    } else {
        Write-Host $message
    }
    exit $code
}

# --------------------------------------------------------------- validation
if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) { Finish $false "payload not found" 2 }

# One read, into memory: the file could be changed underneath us otherwise.
$lines = @([System.IO.File]::ReadAllLines($Payload) | ForEach-Object { $_.TrimEnd("`r") })
$problem = Test-PortcullisPayload -Lines $lines
if ($problem) { Finish $false "refused: the block list did not pass validation ($problem)" 2 }

$entries = @($lines | Where-Object { $_ -like "0.0.0.0 *" }).Count
if ($Check) { Finish $true "valid: $entries entries" 0 }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Finish $false "must run as Administrator" 1
}

try {
    Protect-PortcullisDir -Path $DataDir

    # ------------------------------------------------------------ hosts file
    Copy-Item -LiteralPath $HostsPath "$DataDir\hosts.backup-$(Get-Date -Format yyyyMMddHHmmss)" -Force
    Set-PortcullisBlock -Path $HostsPath -Payload $lines

    # The guard restores from this copy, so it has to match or it would revert the change.
    Write-HostsFile -Path "$DataDir\blocklist.hosts" -Lines $lines

    # --------------------------------------------------- watchdog, first run
    $guardNote = ""
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        Copy-Item (Join-Path $here "guard.ps1") "$DataDir\guard.ps1" -Force
        Copy-Item (Join-Path $here "lib.ps1")   "$DataDir\lib.ps1"   -Force
        Protect-PortcullisDir -Path $DataDir

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DataDir\guard.ps1`""
        $trigger = @(
            (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)),
            (New-ScheduledTaskTrigger -AtStartup)
        )
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description "Restores the Portcullis block list if it is removed." | Out-Null
        $guardNote = "; watchdog installed"
    }

    # ---------------------------------------------- Chrome and Edge policy
    $top = if ($Resources) { Join-Path $Resources "top-domains.txt" } else { $null }
    if ($top -and (Test-Path -LiteralPath $top)) {
        $domains = @(Get-Content -LiteralPath $top | Where-Object { $_ -cmatch $script:HostPattern })
        if ($domains.Count -gt 1000) { $domains = $domains[0..999] }   # the policy's own limit
        foreach ($base in @("HKLM:\SOFTWARE\Policies\Google\Chrome", "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
            $list = "$base\URLBlocklist"
            $existing = Get-Item -Path $list -ErrorAction SilentlyContinue
            if (-not $existing -or $existing.ValueCount -ne $domains.Count) {
                New-Item -Path $list -Force | Out-Null
                Remove-ItemProperty -Path $list -Name * -ErrorAction SilentlyContinue
                for ($i = 0; $i -lt $domains.Count; $i++) {
                    New-ItemProperty -Path $list -Name ($i + 1) -Value $domains[$i] -PropertyType String -Force | Out-Null
                }
            }
            # Stops the browser resolving names itself and skipping the hosts file.
            New-ItemProperty -Path $base -Name "DnsOverHttpsMode" -Value "off" -PropertyType String -Force | Out-Null
        }
    }

    ipconfig /flushdns | Out-Null
    $count = (Select-String -LiteralPath $HostsPath -Pattern '^0\.0\.0\.0 ' -AllMatches).Count
    Finish $true "$count hosts blocked$guardNote" 0
}
catch {
    Finish $false "Couldn't apply: $($_.Exception.Message)" 3
}
