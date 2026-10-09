# Tests the hosts-file handling. Runs anywhere PowerShell runs, including
# macOS and Linux, because it only touches temp files.
#
#   pwsh -File test-lib.ps1

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "lib.ps1")

$pass = 0; $fail = 0
function Check($label, $condition, $detail = "") {
    if ($condition) { $script:pass++; Write-Host "  ok   $label" }
    else { $script:fail++; Write-Host "  FAIL $label $detail" -ForegroundColor Red }
}

$tmp     = Join-Path ([System.IO.Path]::GetTempPath()) "portcullis-test-$PID"
$payload = @("# >>> portcullis >>>", "0.0.0.0 blocked-one.example", "0.0.0.0 blocked-two.example", "# <<< portcullis <<<")
$users   = @("127.0.0.1 localhost", "::1 localhost", "10.0.0.5 my-nas", "0.0.0.0 something-i-added.example")

# --- installing into a clean file -------------------------------------------
Write-HostsFile -Path $tmp -Lines $users
Set-PortcullisBlock -Path $tmp -Payload $payload
$after = @(Get-Content $tmp)

Check "user's own entries survive"      (($users | Where-Object { $after -contains $_ }).Count -eq $users.Count)
Check "block is present"                 (Test-PortcullisIntact -Path $tmp -Payload $payload)
Check "localhost still first"            ($after[0] -eq "127.0.0.1 localhost")

# --- installing twice must not duplicate ------------------------------------
Set-PortcullisBlock -Path $tmp -Payload $payload
$twice = @(Get-Content $tmp)
Check "re-install is idempotent"         ($twice.Count -eq $after.Count) "($($twice.Count) vs $($after.Count) lines)"
Check "only one begin marker"            ((($twice | Where-Object { $_ -eq "# >>> portcullis >>>" }).Count) -eq 1)

# --- tamper detection --------------------------------------------------------
$tampered = $twice | Where-Object { $_ -ne "0.0.0.0 blocked-two.example" }
Write-HostsFile -Path $tmp -Lines $tampered
Check "spots a line deleted from the block" (-not (Test-PortcullisIntact -Path $tmp -Payload $payload))

Set-PortcullisBlock -Path $tmp -Payload $payload
Check "restores after tampering"         (Test-PortcullisIntact -Path $tmp -Payload $payload)

# --- removal -----------------------------------------------------------------
$kept = Remove-PortcullisBlock -Lines @(Get-Content $tmp)
Write-HostsFile -Path $tmp -Lines $kept
$final = @(Get-Content $tmp)
Check "removal leaves no markers"        (-not ($final -match "portcullis"))
Check "removal restores the original"    (-not (Compare-Object $final $users -SyncWindow 0))

# --- a file with no trailing newline, and an empty one ----------------------
[System.IO.File]::WriteAllText($tmp, "127.0.0.1 localhost")
Set-PortcullisBlock -Path $tmp -Payload $payload
Check "handles a file with no trailing newline" (Test-PortcullisIntact -Path $tmp -Payload $payload)

[System.IO.File]::WriteAllText($tmp, "")
Set-PortcullisBlock -Path $tmp -Payload $payload
Check "handles an empty hosts file"      (Test-PortcullisIntact -Path $tmp -Payload $payload)

# --- no byte order mark ------------------------------------------------------
$bytes = [System.IO.File]::ReadAllBytes($tmp)
Check "written without a BOM"            (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))

Remove-Item $tmp -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "  $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
