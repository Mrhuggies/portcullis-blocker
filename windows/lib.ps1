# Shared hosts-file handling for the Windows scripts.
#
# This is the part that touches a file Windows needs to work, so it lives in
# one place and is covered by test-lib.ps1 - which runs on any platform,
# including the Mac this was written on.

$script:Begin = "# >>> portcullis >>>"
$script:End   = "# <<< portcullis <<<"

function Write-HostsFile {
    param([string]$Path, [string[]]$Lines)
    # No BOM: Windows' resolver ignores a hosts file that starts with one.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $utf8)
}

function Remove-PortcullisBlock {
    param([string[]]$Lines)
    $out = @(); $skip = $false
    foreach ($line in $Lines) {
        if ($line -eq $script:Begin) { $skip = $true; continue }
        if ($line -eq $script:End)   { $skip = $false; continue }
        if (-not $skip)              { $out += $line }
    }
    return ,$out
}

function Get-PortcullisBlock {
    param([string[]]$Lines)
    $out = @(); $inside = $false
    foreach ($line in $Lines) {
        if ($line -eq $script:Begin) { $inside = $true }
        if ($inside)                 { $out += $line }
        if ($line -eq $script:End)   { $inside = $false }
    }
    return ,$out
}

function Set-PortcullisBlock {
    param([string]$Path, [string[]]$Payload)
    $existing = @(Get-Content $Path -ErrorAction SilentlyContinue)
    $kept = Remove-PortcullisBlock -Lines $existing
    Write-HostsFile -Path $Path -Lines ($kept + $Payload)
}

function Test-PortcullisIntact {
    param([string]$Path, [string[]]$Payload)
    $current = Get-PortcullisBlock -Lines @(Get-Content $Path -ErrorAction SilentlyContinue)
    if ($current.Count -ne $Payload.Count) { return $false }
    return -not (Compare-Object $current $Payload -SyncWindow 0)
}

# ------------------------------------------------------------------ hardening

function Protect-PortcullisDir {
    # The guard runs as SYSTEM and loads scripts from this folder. If ordinary
    # users could write here - say by creating the folder first - they could
    # swap those scripts for their own and have Windows run them as SYSTEM.
    # So: owned by Administrators; SYSTEM and Administrators full; Users read.
    # SIDs rather than names, so it works on non-English Windows.
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    if ($env:OS -ne "Windows_NT") { return }      # tests run on other systems
    & icacls.exe $Path /setowner "*S-1-5-32-544" /T /C /Q | Out-Null
    & icacls.exe $Path /inheritance:r /grant:r `
        "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /T /C /Q | Out-Null
}

# ---------------------------------------------------------------- validation

$script:HostPattern = '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+$'

function Test-PortcullisPayload {
    # The payload is written by the panel, running as an ordinary user, so the
    # elevated side must not trust it. The only thing allowed between the
    # markers is "0.0.0.0 <hostname>" - which means applying it can only ever
    # BLOCK names, never point a real site at someone else's server.
    # Returns $null if the lines are acceptable, or the reason they aren't.
    param([string[]]$Lines)
    if ($Lines.Count -gt 500000) { return "too many lines" }
    $state = 0; $n = 0
    foreach ($raw in $Lines) {
        $n++
        $line = $raw.TrimEnd("`r")
        if ($line -eq $script:Begin) {
            if ($state -ne 0) { return "duplicate begin marker" }
            $state = 1; continue
        }
        if ($line -eq $script:End) {
            if ($state -ne 1) { return "end marker out of place" }
            $state = 2; continue
        }
        if ($state -ne 1) {
            if ($line -ne "") { return "content outside the markers" }
            continue
        }
        if ($line.StartsWith("# ")) { continue }
        $parts = $line.Split(" ")
        if ($parts.Count -eq 2 -and $parts[0] -ceq "0.0.0.0" -and $parts[1] -cmatch $script:HostPattern) { continue }
        return ("line {0} is not a block entry" -f $n)
    }
    if ($state -ne 2) { return "missing end marker" }
    return $null
}
