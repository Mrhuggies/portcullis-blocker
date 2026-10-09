# Tests the panel's rules - the same ones app/test_server.py checks for the
# Mac. Runs anywhere PowerShell runs; nothing touches the real system.
#
#   pwsh -File test-panel.ps1

$ErrorActionPreference = "Stop"
$env:PORTCULLIS_HOME  = Join-Path ([IO.Path]::GetTempPath()) "portcullis-panel-test-$PID"
$env:PORTCULLIS_HOSTS = Join-Path $env:PORTCULLIS_HOME "hosts"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "panel.ps1")
. (Join-Path $here "lib.ps1")

$pass = 0; $fail = 0
function Check($label, $condition, $detail = "") {
    if ($condition) { $script:pass++; Write-Host "  ok   $label" }
    else { $script:fail++; Write-Host "  FAIL $label $detail" -ForegroundColor Red }
}
function Refuses($block) { try { & $block; return $false } catch [Refused] { return $true } }
function Fresh {
    $d = Get-State
    $d.sites = New-Object System.Collections.ArrayList; $d.pending = @{}; $d.pendingTools = @{}
    $d.waitHours = 48; $d.pendingWait = $null; $d.released = New-Object System.Collections.ArrayList
    return $d
}
function Act($d, $req) { Invoke-Act $d $req | Out-Null }

Write-Host "Addresses"
$cases = [ordered]@{
    "https://www.Example.com/a?b#c" = "example.com"; "user@example.co.uk:8080/x" = "example.co.uk"
    "  sub.example.com.  " = "sub.example.com"; "not a site" = $null; "localhost" = $null
    "192.168.1.1" = $null; "" = $null; "exa mple.com" = $null; "-bad.com" = $null
    ("x" * 300 + ".com") = $null; "EXAMPLE.ORG" = "example.org"
}
foreach ($k in $cases.Keys) { Check "normalise '$($k.Substring(0, [Math]::Min(30, $k.Length)))'" ((ConvertTo-HostName $k) -eq $cases[$k]) }
Check "normalise null" ($null -eq (ConvertTo-HostName $null))

Write-Host "Rules"
$d = Fresh; Act $d @{ action = "addSite"; host = "example.com" }
$want = Get-DesiredHosts $d
Check "adding is instant"            ($want.Contains("example.com") -and $want.Contains("www.example.com"))
Check "duplicates refused"           (Refuses { Act $d @{ action = "addSite"; host = "https://www.example.com/" } })

Act $d @{ action = "requestRemoval"; host = "example.com" }
[void](Invoke-Tick $d)
Check "removal waits"                ($d.sites.Count -eq 1)
$first = $d.pending["example.com"]; Start-Sleep -Milliseconds 20
Act $d @{ action = "requestRemoval"; host = "example.com" }
Check "asking twice keeps the clock" ($d.pending["example.com"] -eq $first)
$d.pending["example.com"] = (Now) - 1; [void](Invoke-Tick $d)
Check "removal after the wait"       ($d.sites.Count -eq 0)

$d = Fresh; Act $d @{ action = "addSite"; host = "example.com" }
Act $d @{ action = "requestRemoval"; host = "example.com" }; Act $d @{ action = "cancelRemoval"; host = "example.com" }
Check "cancel keeps it"              ($d.pending.Count -eq 0 -and $d.sites.Count -eq 1)

$d = Fresh
Act $d @{ action = "setTool"; id = "nordvpn"; on = $true }
Check "tool on is instant"           ($d.tools["nordvpn"] -eq $true)
Act $d @{ action = "setTool"; id = "nordvpn"; on = $false }
Check "tool off waits"               ($d.tools["nordvpn"] -eq $true -and $d.pendingTools.ContainsKey("nordvpn"))
Act $d @{ action = "setTool"; id = "nordvpn"; on = $false }
Check "second click keeps it on"     (-not $d.pendingTools.ContainsKey("nordvpn"))
Act $d @{ action = "setTool"; id = "nordvpn"; on = $false }
$d.pendingTools["nordvpn"] = (Now) - 1; [void](Invoke-Tick $d)
Check "tool off after the wait"      ($d.tools["nordvpn"] -eq $false)
Check "unknown tool refused"         (Refuses { Act $d @{ action = "setTool"; id = "nope"; on = $true } })
Check "non-bool refused"             (Refuses { Act $d @{ action = "setTool"; id = "tor"; on = "yes" } })
Check "unknown action refused"       (Refuses { Act $d @{ action = "rm -rf" } })
Check "array action refused"         (Refuses { Act $d @{ action = @("cancelWait", "x") } })

$d = Fresh
Act $d @{ action = "setWait"; hours = 72 }
Check "raising the wait is instant"  ($d.waitHours -eq 72)
Act $d @{ action = "setWait"; hours = 1 }
Check "lowering the wait waits"      ($d.waitHours -eq 72 -and $d.pendingWait.hours -eq 1)
foreach ($bad in "abc", $null, @(), @{}) { Check "bad wait '$bad' refused" (Refuses { Act $d @{ action = "setWait"; hours = $bad } }) }
Act $d @{ action = "setWait"; hours = 99999 }
Check "wait capped at 720"           ($d.waitHours -eq 720)

Write-Host "Only released hosts come off"
$d = Fresh
$installed = @("x.com", "www.x.com", "my-own-block.example")
$out = Get-PayloadHosts $d $installed
Check "existing blocks are kept"     (@($installed | Where-Object { $out.Contains($_) }).Count -eq 3)

Act $d @{ action = "addSite"; host = "example.com" }
$inst = Get-PayloadHosts $d @()
Act $d @{ action = "requestRemoval"; host = "example.com" }
Check "not before the wait"          ((Get-PayloadHosts $d $inst).Contains("example.com"))
$d.pending["example.com"] = (Now) - 1; [void](Invoke-Tick $d)
$out = Get-PayloadHosts $d $inst
Check "finished removal comes off"   (-not ($out.Contains("example.com") -or $out.Contains("www.example.com") -or $out.Contains("m.example.com")))

$d = Fresh
Act $d @{ action = "setTool"; id = "nordvpn"; on = $true }
$inst = Get-PayloadHosts $d @()
Act $d @{ action = "setTool"; id = "nordvpn"; on = $false }
$d.pendingTools["nordvpn"] = (Now) - 1; [void](Invoke-Tick $d)
Check "finished tool-off comes off"  (-not (Get-PayloadHosts $d $inst).Contains("nordvpn.com"))

$d = Fresh
Add-Released $d (Get-SiteVariants "example.com")
Act $d @{ action = "addSite"; host = "example.com" }
Check "re-adding a released site"    ((Get-PayloadHosts $d @()).Contains("example.com"))

Write-Host "Payload and saved state"
New-Item -ItemType Directory -Force -Path $env:PORTCULLIS_HOME | Out-Null
[IO.File]::WriteAllLines($HostsPath, @("127.0.0.1 localhost", $Begin, "0.0.0.0 x.com", "0.0.0.0 bad_entry", $End))
$d = Fresh; Act $d @{ action = "addSite"; host = "example.com" }
$p = (Get-Payload $d).TrimEnd("`n").Split("`n")
Check "payload passes the elevated validator" ($null -eq (Test-PortcullisPayload -Lines $p)) (Test-PortcullisPayload -Lines $p)
Check "payload keeps the hand-added block"    ($p -contains "0.0.0.0 x.com")
Check "payload drops a malformed entry"       ($p -notcontains "0.0.0.0 bad_entry")
$hosts = @($p | Where-Object { $_ -like "0.0.0.0 *" })
Check "no duplicates in payload"              (@($hosts | Select-Object -Unique).Count -eq $hosts.Count)
$s = Get-Status $d
Check "status counts kept and pending"        ($s.installed -and $s.kept -ge 1 -and $s.toAdd -gt 0 -and -not $s.upToDate)

Save-State $d
$back = Get-State
Check "state round-trips"                     ($back.sites[0].host -eq "example.com" -and $back.waitHours -eq 48)
Check "no temp file left behind"              (@(Get-ChildItem $env:PORTCULLIS_HOME -Filter ".user.*.json" -Force).Count -eq 0)
$single = Get-State; Save-State $single; $again = Get-State
Check "one-item lists stay lists"             ($again.sites -is [System.Collections.ArrayList] -and $again.sites.Count -eq 1)

[IO.File]::WriteAllText($StatePath, "{ this is not json")
$script:Corrupt = $false
$x = Get-State
Check "damaged file is set aside"             ($script:Corrupt -and @(Get-ChildItem $env:PORTCULLIS_HOME -Filter "user.damaged-*.json").Count -eq 1)
$why = try { Invoke-Apply $x } catch [Refused] { $_.Exception.Message }
Check "damaged state won't apply"             ($why -like "*damaged*") $why

Remove-Item -Recurse -Force $env:PORTCULLIS_HOME
Write-Host ""
Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
