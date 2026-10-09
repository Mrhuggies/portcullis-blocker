# Tests the validation in apply-payload.ps1 - the script that runs with
# Administrator rights - using its -Check mode, which needs no admin. The same
# cases as mac/test-apply-payload.sh.
#
#   pwsh -File test-apply-payload.ps1

$ErrorActionPreference = "Stop"
$script = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "apply-payload.ps1"
$exe = (Get-Process -Id $PID).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) "portcullis-apply-test-$PID.hosts"
$B = "# >>> portcullis >>>"; $E = "# <<< portcullis <<<"
$pass = 0; $fail = 0

function Expect($want, $label, [string]$content) {
    [IO.File]::WriteAllText($tmp, $content)
    & $exe -NoProfile -File $script -Payload $tmp -Check *> $null
    $got = if ($LASTEXITCODE -eq 0) { "accept" } else { "reject" }
    if ($got -eq $want) { $script:pass++; Write-Host "  ok   $label" }
    else { $script:fail++; Write-Host "  FAIL $label (expected $want, got $got)" -ForegroundColor Red }
}
$n = "`n"

Expect accept "a normal block"                 "$B$n# Generated$n0.0.0.0 example.com${n}0.0.0.0 www.example.com$n$E$n"
Expect accept "Windows line endings"           "$B`r${n}0.0.0.0 example.com`r$n$E`r$n"
Expect reject "redirect a real site elsewhere" "$B${n}6.6.6.6 bank.com$n$E$n"
Expect reject "point a site at localhost"      "$B${n}127.0.0.1 bank.com$n$E$n"
Expect reject "a second name on one line"      "$B${n}0.0.0.0 a.com b.com$n$E$n"
Expect reject "shell metacharacters"           "$B${n}0.0.0.0 a.com;calc$n$E$n"
Expect reject "missing end marker"             "$B${n}0.0.0.0 a.com$n"
Expect reject "content outside the markers"    "127.0.0.1 evil$n$B${n}0.0.0.0 a.com$n$E$n"
Expect reject "duplicate begin marker"         "$B$n$B${n}0.0.0.0 a.com$n$E$n"
Expect reject "uppercase / invalid hostname"   "$B${n}0.0.0.0 Bank.COM$n$E$n"
Expect reject "a bare IP, no name"             "$B${n}0.0.0.0$n$E$n"
Expect reject "empty file"                     ""

Remove-Item $tmp -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
