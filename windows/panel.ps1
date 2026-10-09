# Portcullis control panel for Windows.
#
# A small web server on this computer that serves the interface to your
# browser - the Windows twin of app/server.py, following exactly the same
# rules. The only privileged step, writing the hosts file, goes through the
# Windows permission (UAC) prompt, and the elevated side refuses anything that
# isn't a block.
#
# Started by Portcullis.cmd. Quits itself after 15 idle minutes, or from the
# Quit button in Settings.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

class Refused : System.Exception { Refused([string]$m) : base($m) {} }

# ---------------------------------------------------------------- settings
$Port      = if ($env:PORTCULLIS_PORT) { [int]$env:PORTCULLIS_PORT } else { 7378 }
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path      # ...\app\windows
$AppDir    = Split-Path -Parent $Here                              # ...\app
if (-not (Test-Path (Join-Path $AppDir "tools.json"))) {           # run from the source tree
    $AppDir = Join-Path $AppDir "app"
}
$Root      = Split-Path -Parent $AppDir                            # the unzipped folder
$OnWindows = $env:OS -eq "Windows_NT"
$StateDir  = if ($env:PORTCULLIS_HOME) { $env:PORTCULLIS_HOME } else { Join-Path $env:APPDATA "Portcullis" }
$StatePath = Join-Path $StateDir "user.json"
$HostsPath = if ($env:PORTCULLIS_HOSTS) { $env:PORTCULLIS_HOSTS } else { "$env:SystemRoot\System32\drivers\etc\hosts" }
$Begin     = "# >>> portcullis >>>"
$End       = "# <<< portcullis <<<"
$HostRe    = '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+$'
$Allowed   = @("localhost:$Port", "127.0.0.1:$Port")
$IdleSecs  = 15 * 60
$Utf8      = New-Object System.Text.UTF8Encoding($false)
$script:Corrupt = $false

# Generated once per launch. The page gets it; other websites can't read it,
# so they can't drive the panel even though it's on your computer.
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$Token = [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")

function Now { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0 }

# ------------------------------------------------------------------ state
function ConvertTo-Hash($o) {
    # ConvertFrom-Json in Windows PowerShell 5.1 has no -AsHashtable.
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    if ($o -is [System.Collections.IList] -and $o -isnot [string]) {
        $a = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$a.Add((ConvertTo-Hash $i)) }
        return ,$a
    }
    return $o
}

$script:CatalogueCache = $null
function Get-Catalogue {
    if (-not $script:CatalogueCache) {
        $script:CatalogueCache = @(([IO.File]::ReadAllText((Join-Path $AppDir "tools.json")) | ConvertFrom-Json).tools)
    }
    return $script:CatalogueCache
}

function New-State {
    @{ sites = (New-Object System.Collections.ArrayList); tools = @{}; pending = @{};
       pendingTools = @{}; waitHours = 48; pendingWait = $null;
       released = (New-Object System.Collections.ArrayList) }
}

function Get-State {
    # A damaged file is set aside, never silently replaced: starting from
    # defaults would quietly drop someone's list on the next Apply.
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $d = New-State
    if (Test-Path -LiteralPath $StatePath) {
        try {
            $saved = ConvertTo-Hash ([IO.File]::ReadAllText($StatePath) | ConvertFrom-Json)
            if ($saved -isnot [hashtable]) { throw "not an object" }
            foreach ($k in @($saved.Keys)) { $d[$k] = $saved[$k] }
            $script:Corrupt = $false
        } catch {
            if (-not $script:Corrupt) {
                Rename-Item -LiteralPath $StatePath -NewName ("user.damaged-{0}.json" -f [long](Now))
            }
            $script:Corrupt = $true
        }
    }
    foreach ($k in "tools", "pending", "pendingTools") { if ($d[$k] -isnot [hashtable]) { $d[$k] = @{} } }
    foreach ($k in "sites", "released") {
        if ($d[$k] -isnot [System.Collections.ArrayList]) {
            $d[$k] = [System.Collections.ArrayList]@(@($d[$k]) | Where-Object { $null -ne $_ })
        }
    }
    $tools = @{}
    foreach ($t in Get-Catalogue) {
        $tools[$t.id] = if ($d.tools.ContainsKey($t.id)) { [bool]$d.tools[$t.id] } else { [bool]$t.default }
    }
    $d.tools = $tools
    return $d
}

function Save-State($d) {
    # Write to a temp file, then swap it in, so a crash can't leave half a file.
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $tmp = Join-Path $StateDir (".user.{0}.json" -f [guid]::NewGuid().ToString("N"))
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json $d -Depth 10), $Utf8)
    if (Test-Path -LiteralPath $StatePath) { [IO.File]::Replace($tmp, $StatePath, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $StatePath) }
}

# ------------------------------------------------------------------ rules
function ConvertTo-HostName($raw) {
    $s = ("" + $raw).Trim().ToLowerInvariant()
    $s = $s -replace '^[a-z][a-z0-9+.-]*://', ''
    $s = ($s -split '[/?#]')[0]
    $s = ($s -split '@')[-1]
    $s = ($s -split ':')[0]
    $s = ($s -replace '^www\.', '').TrimEnd('.')
    if ($s.Length -gt 253 -or $s -cnotmatch $HostRe -or $s -cnotmatch '\.[a-z]{2,}$') { return $null }
    return $s
}

function Get-SiteVariants($h) { @($h, "www.$h", "m.$h") }

function Add-Released($d, $hosts) {
    $set = New-Object System.Collections.Generic.SortedSet[string]
    foreach ($h in @($d.released) + @($hosts)) { if ($h) { [void]$set.Add([string]$h) } }
    $d.released = [System.Collections.ArrayList]@($set)
}

function Invoke-Tick($d) {
    # Apply anything whose waiting period is over. Finished removals are recorded
    # as released - the only thing Apply is ever allowed to take out of the file.
    $now = Now; $changed = $false
    foreach ($h in @($d.pending.Keys)) {
        if ($now -ge [double]$d.pending[$h]) {
            $d.sites = [System.Collections.ArrayList]@($d.sites | Where-Object { $_.host -ne $h })
            $d.pending.Remove($h)
            Add-Released $d (Get-SiteVariants $h)
            $changed = $true
        }
    }
    foreach ($t in @($d.pendingTools.Keys)) {
        if ($now -ge [double]$d.pendingTools[$t]) {
            $d.tools[$t] = $false
            $d.pendingTools.Remove($t)
            $tool = Get-Catalogue | Where-Object { $_.id -eq $t }
            if ($tool) { Add-Released $d @($tool.domains) }
            $changed = $true
        }
    }
    if ($d.pendingWait -and $now -ge [double]$d.pendingWait.at) {
        $d.waitHours = [int]$d.pendingWait.hours
        $d.pendingWait = $null
        $changed = $true
    }
    return $changed
}

function Invoke-Act($d, $req) {
    # Every change the panel can make. Tightening is instant; loosening waits.
    $wait = [double]$d.waitHours * 3600
    switch ([string]$req.action) {
        "addSite" {
            $h = ConvertTo-HostName $req.host
            if (-not $h) { throw [Refused]::new("That doesn't look like a website address.") }
            if (@($d.sites | Where-Object { $_.host -eq $h }).Count) { throw [Refused]::new("$h is already on your list.") }
            [void]$d.sites.Add(@{ host = $h; added = (Now) })
            $d.pending.Remove($h)
            return "$h added."
        }
        { $_ -in "requestRemoval", "cancelRemoval" } {
            $h = ConvertTo-HostName $req.host
            if (-not $h -or -not @($d.sites | Where-Object { $_.host -eq $h }).Count) {
                throw [Refused]::new("That site isn't on your list.")
            }
            if ($req.action -eq "cancelRemoval") { $d.pending.Remove($h); return "$h stays blocked." }
            if (-not $d.pending.ContainsKey($h)) { $d.pending[$h] = (Now) + $wait }
            return "$h will come off after the waiting period."
        }
        "setTool" {
            $id = [string]$req.id; $on = $req.on
            if (-not $d.tools.ContainsKey($id) -or $on -isnot [bool]) { throw [Refused]::new("Unknown setting.") }
            if ($on) { $d.tools[$id] = $true; $d.pendingTools.Remove($id); return "Blocked." }
            if ($d.pendingTools.ContainsKey($id)) { $d.pendingTools.Remove($id); return "Kept on." }
            $d.pendingTools[$id] = (Now) + $wait
            return "Will switch off after the waiting period."
        }
        "setWait" {
            $v = $req.hours
            $isNum = ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or
                      ($v -is [string] -and $v -match '^\s*\d+\s*$'))
            if (-not $isNum) { throw [Refused]::new("Give it a number of hours.") }
            $hours = [Math]::Max(1, [Math]::Min(720, [int][Math]::Truncate([double]$v)))
            if ($hours -ge $d.waitHours) {
                $d.waitHours = $hours; $d.pendingWait = $null
                return "Waiting period is now $hours hours."
            }
            $d.pendingWait = @{ hours = $hours; at = (Now) + $wait }
            return "Will drop to $hours hours once the current waiting period has passed."
        }
        "cancelWait" { $d.pendingWait = $null; return "Kept as it is." }
    }
    throw [Refused]::new("Unknown action.")
}

# ---------------------------------------------------------------- payload
$script:Base = $null
function Get-BaseHosts {
    if (-not $script:Base) {
        $list = New-Object System.Collections.Generic.List[string]
        foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root "blocklist.hosts"))) {
            if ($l.StartsWith("0.0.0.0 ")) {
                $p = $l.Split(" ")
                if ($p.Count -eq 2) { $list.Add($p[1]) }
            }
        }
        $script:Base = $list
    }
    return $script:Base
}

function Get-DesiredHosts($d) {
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $out  = New-Object System.Collections.Generic.List[string]
    $extra = New-Object System.Collections.Generic.List[string]
    foreach ($t in Get-Catalogue) { if ($d.tools[$t.id]) { foreach ($x in $t.domains) { $extra.Add($x) } } }
    foreach ($s in $d.sites) { foreach ($x in (Get-SiteVariants $s.host)) { $extra.Add($x) } }
    foreach ($h in (Get-BaseHosts)) { if ($seen.Add($h)) { $out.Add($h) } }
    foreach ($h in $extra) { if ($h -cmatch $HostRe -and $seen.Add($h)) { $out.Add($h) } }
    return ,$out
}

$script:Installed = $null; $script:InstalledStamp = $null
function Get-InstalledHosts {
    # Re-read only when the hosts file changes; it's tens of thousands of lines.
    if (-not (Test-Path -LiteralPath $HostsPath)) { return $null }
    $stamp = (Get-Item -LiteralPath $HostsPath).LastWriteTimeUtc.Ticks
    if ($stamp -eq $script:InstalledStamp) { return ,$script:Installed }
    $lines = [IO.File]::ReadAllLines($HostsPath)
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false; $found = $false
    foreach ($l in $lines) {
        if ($l -eq $Begin) { $inside = $true; $found = $true; continue }
        if ($l -eq $End)   { $inside = $false; continue }
        if ($inside -and $l.StartsWith("0.0.0.0 ")) { $out.Add($l.Split(" ")[1]) }
    }
    $script:Installed = if ($found) { $out } else { $null }
    $script:InstalledStamp = $stamp
    return ,$script:Installed
}

function Get-PayloadHosts($d, $installed) {
    # Everything wanted, plus anything already blocked that hasn't been
    # released. Without the second part, entries from an earlier setup - or
    # blocks someone added by hand - would vanish with no wait at all.
    $want = Get-DesiredHosts $d
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($h in $want) { [void]$seen.Add($h) }
    $released = New-Object System.Collections.Generic.HashSet[string]
    foreach ($h in $d.released) { [void]$released.Add([string]$h) }
    if ($installed) {
        foreach ($h in $installed) {
            if (-not $released.Contains($h) -and $h -cmatch $HostRe -and $seen.Add($h)) { $want.Add($h) }
        }
    }
    return ,$want
}

function Get-Payload($d) {
    $hosts = Get-PayloadHosts $d (Get-InstalledHosts)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Begin)
    $lines.Add(("# Generated by Portcullis - {0:N0} hosts." -f $hosts.Count))
    foreach ($h in $hosts) { $lines.Add("0.0.0.0 $h") }
    $lines.Add($End)
    return ($lines -join "`n") + "`n"
}

function Get-Status($d) {
    $current = Get-InstalledHosts
    $have = New-Object System.Collections.Generic.HashSet[string]
    if ($current) { foreach ($h in $current) { [void]$have.Add($h) } }
    $want = New-Object System.Collections.Generic.HashSet[string]
    foreach ($h in (Get-DesiredHosts $d)) { [void]$want.Add($h) }
    $target = New-Object System.Collections.Generic.HashSet[string]
    foreach ($h in (Get-PayloadHosts $d $current)) { [void]$target.Add($h) }

    $toAdd = 0; $kept = 0
    foreach ($h in $target) { if (-not $have.Contains($h)) { $toAdd++ }; if (-not $want.Contains($h)) { $kept++ } }
    $toRemove = 0
    foreach ($h in $have) { if (-not $target.Contains($h)) { $toRemove++ } }

    $guard = $false; $lock = $false
    if ($OnWindows) {
        $guard = [bool](Get-ScheduledTask -TaskName "Portcullis Guard" -ErrorAction SilentlyContinue)
        $lock  = Test-Path "HKLM:\SOFTWARE\Policies\Google\Chrome\URLBlocklist"
    }
    @{ installed = ($null -ne $current); count = $have.Count;
       upToDate = ($null -ne $current -and $toAdd -eq 0 -and $toRemove -eq 0);
       toAdd = $toAdd; toRemove = $toRemove; kept = $kept;
       guard = $guard; chromeProfile = $lock; corrupt = $script:Corrupt; os = "windows" }
}

function Invoke-Apply($d) {
    if ($script:Corrupt) {
        throw [Refused]::new("Your saved settings were damaged, so I won't apply them. A copy is in $StateDir.")
    }
    if (-not $OnWindows) { throw [Refused]::new("Applying needs Windows.") }
    $payload = Join-Path $StateDir "payload.hosts"
    [IO.File]::WriteAllText($payload, (Get-Payload $d), $Utf8)
    $result = Join-Path $env:TEMP ("portcullis-result-{0}.json" -f [guid]::NewGuid().ToString("N"))
    $q = { param($s) '"' + ([string]$s).Replace('"', '') + '"' }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                 "-File", (& $q (Join-Path $Here "apply-payload.ps1")),
                 "-Payload", (& $q $payload), "-Resources", (& $q $Root), "-Result", (& $q $result)) -join " "
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList $argList | Out-Null
    } catch {
        throw [Refused]::new("You said no to the Windows permission prompt, so nothing changed.")
    }
    if (-not (Test-Path -LiteralPath $result)) { throw [Refused]::new("Couldn't apply: no result came back.") }
    $r = [IO.File]::ReadAllText($result) | ConvertFrom-Json
    Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue
    $script:InstalledStamp = $null
    if (-not $r.ok) { throw [Refused]::new([string]$r.message) }
    return [string]$r.message
}

# ----------------------------------------------------------------- server
$script:Index = $null
function Get-Index {
    if (-not $script:Index) {
        $html = [IO.File]::ReadAllText((Join-Path $AppDir "ui\index.html")).Replace("__PORTCULLIS_TOKEN__", $Token)
        $script:Index = $Utf8.GetBytes($html)
    }
    return ,$script:Index
}

function Send($ctx, [int]$code, $body, [string]$type = "application/json") {
    $res = $ctx.Response
    if ($body -isnot [byte[]]) { $body = $Utf8.GetBytes((ConvertTo-Json $body -Depth 10 -Compress)) }
    $res.StatusCode = $code
    $res.ContentType = "$type; charset=utf-8"
    $res.Headers["Cache-Control"] = "no-store"
    $res.Headers["X-Content-Type-Options"] = "nosniff"
    $res.Headers["Content-Security-Policy"] = "default-src 'self'; script-src 'unsafe-inline'; " +
        "style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"
    $res.ContentLength64 = $body.Length
    $res.OutputStream.Write($body, 0, $body.Length)
    $res.OutputStream.Close()
}

function Test-Trusted($req, [bool]$needToken) {
    # Only this computer may connect: Windows listens on every network
    # interface even for a "localhost" address.
    $ip = $req.RemoteEndPoint.Address
    if (-not $ip -or -not [System.Net.IPAddress]::IsLoopback($ip)) { return $false }
    # Host check defeats DNS rebinding.
    if ($Allowed -notcontains $req.Headers["Host"]) { return $false }
    $origin = $req.Headers["Origin"]
    if ($origin) {
        try { if ($Allowed -notcontains ([Uri]$origin).Authority) { return $false } } catch { return $false }
    }
    if (-not $needToken) { return $true }
    # A custom header can't be sent cross-site without a CORS preflight,
    # which this server never approves.
    return Test-SameText ([string]$req.Headers["X-Portcullis-Token"]) $Token
}

function Test-SameText([string]$a, [string]$b) {
    # Constant-time, so response timing can't leak the token a character at a time.
    $x = $Utf8.GetBytes($a); $y = $Utf8.GetBytes($b)
    $diff = $x.Length -bxor $y.Length
    for ($i = 0; $i -lt [Math]::Min($x.Length, $y.Length); $i++) { $diff = $diff -bor ($x[$i] -bxor $y[$i]) }
    return $diff -eq 0
}

function Invoke-Request($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath

    if ($req.HttpMethod -eq "GET") {
        if ($path -eq "/api/hello") {
            if (Test-Trusted $req $false) { return Send $ctx 200 @{ app = "portcullis" } }
            return Send $ctx 403 @{}
        }
        if (-not (Test-Trusted $req $path.StartsWith("/api/"))) { return Send $ctx 403 @{ error = "forbidden" } }
        if ($path -eq "/" -or $path -eq "/index.html") { return Send $ctx 200 (Get-Index) "text/html" }
        # The setup guide and its pictures. Names are matched by pattern and
        # looked up in one folder, so nothing else on disk can be reached.
        if ($path -eq "/guide.html") {
            return Send $ctx 200 ([IO.File]::ReadAllBytes((Join-Path $AppDir "ui\guide.html"))) "text/html"
        }
        if ($path -cmatch '^/img/([a-z0-9-]+)\.(png|jpg)$') {
            $file = Join-Path $AppDir ("ui\img\{0}.{1}" -f $Matches[1], $Matches[2])
            $type = if ($Matches[2] -eq "png") { "image/png" } else { "image/jpeg" }
            if (Test-Path -LiteralPath $file -PathType Leaf) { return Send $ctx 200 ([IO.File]::ReadAllBytes($file)) $type }
        }
        if ($path -eq "/api/state") {
            $d = Get-State
            if ((Invoke-Tick $d) -and -not $script:Corrupt) { Save-State $d }
            return Send $ctx 200 @{ state = $d; status = (Get-Status $d); catalogue = @(Get-Catalogue) }
        }
        return Send $ctx 404 @{ error = "not found" }
    }

    if ($req.HttpMethod -ne "POST") { return Send $ctx 405 @{ error = "method not allowed" } }
    if (-not (Test-Trusted $req $true)) { return Send $ctx 403 @{ error = "forbidden" } }
    if ($req.ContentLength64 -gt 65536) { return Send $ctx 400 @{ ok = $false; error = "Bad request." } }

    try {
        $reader = New-Object System.IO.StreamReader($req.InputStream, $Utf8)
        $body = ConvertTo-Hash ($reader.ReadToEnd() | ConvertFrom-Json)
        if ($body -isnot [hashtable]) { throw "not an object" }
    } catch {
        return Send $ctx 400 @{ ok = $false; error = "Bad request." }
    }

    if ($body.action -eq "openProfile") {
        # The Mac needs a profile approved by hand; on Windows the browser lock
        # is set by Turn on itself.
        return Send $ctx 200 @{ ok = $false; error = "Not needed on Windows - Turn on sets the Chrome and Edge lock." }
    }

    if ($body.action -eq "quit") {
        Send $ctx 200 @{ ok = $true }
        $script:Quit = $true
        return
    }

    $d = Get-State
    [void](Invoke-Tick $d)
    try {
        if ($body.action -eq "apply") {
            Save-State $d
            $msg = Invoke-Apply $d
            $d.released = New-Object System.Collections.ArrayList
            Save-State $d
        } else {
            if ($script:Corrupt) { throw [Refused]::new("Your saved settings were damaged - restart the panel to begin fresh.") }
            $msg = Invoke-Act $d $body
            Save-State $d
        }
        Send $ctx 200 @{ ok = $true; message = $msg; state = $d; status = (Get-Status $d) }
    } catch [Refused] {
        Send $ctx 200 @{ ok = $false; error = $_.Exception.Message; state = $d; status = (Get-Status $d) }
    } catch {
        Send $ctx 500 @{ ok = $false; error = "Something went wrong: $($_.Exception.Message)" }
    }
}

function Show-Message($text) {
    if (-not $OnWindows) { Write-Host $text; return }
    try { (New-Object -ComObject WScript.Shell).Popup($text, 0, "Portcullis", 0x30) | Out-Null } catch { }
}

function Test-OurPanel {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 "http://localhost:$Port/api/hello"
        return $r.Content -match '"portcullis"'
    } catch { return $false }
}

# ------------------------------------------------------------------- main
# Dot-sourcing (". .\panel.ps1") loads the functions without starting the
# server; test-panel.ps1 uses that.
if ($MyInvocation.InvocationName -eq ".") { return }

$url = "http://localhost:$Port/"
if (Test-OurPanel) {
    if (-not $env:PORTCULLIS_NO_BROWSER) { Start-Process $url }
    exit 0
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
try {
    $listener.Start()
} catch {
    Show-Message "Port $Port is being used by another program, so the Portcullis panel can't start. Quit it and try again."
    exit 3
}

Write-Host "Portcullis panel on $url"
if (-not $env:PORTCULLIS_NO_BROWSER) { Start-Process $url }

$script:Quit = $false
$last = Now
try {
    while (-not $script:Quit) {
        $pending = $listener.GetContextAsync()
        while (-not $pending.Wait(1000)) {
            if ((Now) - $last -gt $IdleSecs) { $script:Quit = $true; break }
        }
        if ($script:Quit) { break }
        $last = Now
        try { Invoke-Request $pending.Result } catch { }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
