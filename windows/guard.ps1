# Puts the block back if it is removed or edited.
# Run every few minutes by a scheduled task created by install-guard.ps1.
#
# It stands down once a removal request has waited out its 48 hours, so
# uninstall.ps1 can finish the job without a fight.

$ErrorActionPreference = "Stop"

$Begin     = "# >>> portcullis >>>"
$End       = "# <<< portcullis <<<"
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$DataDir   = "$env:ProgramData\Portcullis"
$Payload   = "$DataDir\blocklist.hosts"
$Request   = "$DataDir\removal-requested"
$Log       = "$DataDir\guard.log"
$WaitHours = 48

. (Join-Path $DataDir "lib.ps1")

function Say($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Add-Content -Path $Log -Encoding utf8
}

if (-not (Test-Path $Payload)) { exit 0 }

# A matured removal request means the wait was served. Leave it alone.
if (Test-Path $Request) {
    $raw = (Get-Content $Request -Raw).Trim()
    [datetime]$when = [datetime]::MinValue
    if ([datetime]::TryParse($raw, [ref]$when)) {
        if ((Get-Date) -ge $when.AddHours($WaitHours)) { exit 0 }
    }
}

$expected = @(Get-Content $Payload)
if (Test-PortcullisIntact -Path $HostsPath -Payload $expected) { exit 0 }

Set-PortcullisBlock -Path $HostsPath -Payload $expected
ipconfig /flushdns | Out-Null

$count = (Select-String -Path $HostsPath -Pattern '^0\.0\.0\.0 ' -AllMatches).Count
Say "restored hosts block ($count entries)"

# A toast if the machine has anyone looking at it.
try {
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.Popup("The block was removed. It has been put back.", 5, "Portcullis", 0x40) | Out-Null
} catch { }
