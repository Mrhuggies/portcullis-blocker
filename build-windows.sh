#!/bin/bash
# Builds Portcullis-Windows.zip from the source in this folder. Always rebuild
# rather than editing the zipped copy, so what ships is exactly what was tested.
#
#   bash build-windows.sh            (needs pwsh on the PATH, or PWSH=/path/to/pwsh)

set -euo pipefail
cd "$(dirname "$0")"
PWSH="${PWSH:-$(command -v pwsh || true)}"
[[ -x "$PWSH" ]] || { echo "PowerShell (pwsh) is needed to run the tests." >&2; exit 1; }

echo "Running tests first..."
# Windows PowerShell 5.1 reads a script without a byte-order mark as ANSI, so
# one em dash inside a string can turn into a stray quote and break parsing.
if LC_ALL=C grep -n '[^ -~	]' windows/*.ps1; then
  echo "Non-ASCII characters in the scripts above — replace them." >&2; exit 1
fi
for f in windows/*.ps1; do
  "$PWSH" -NoProfile -Command "\$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$PWD/$f',[ref]\$null,[ref]\$e); if(\$e){\$e | % { Write-Error \"$f \$(\$_.Extent.StartLineNumber): \$(\$_.Message)\" }; exit 1}"
done
"$PWSH" -NoProfile -File windows/test-lib.ps1   | tail -1
"$PWSH" -NoProfile -File windows/test-panel.ps1 | tail -1
"$PWSH" -NoProfile -File windows/test-apply-payload.ps1 | tail -1
PWSH="$PWSH" python3 -m unittest windows/test_panel.py 2>&1 | tail -1
python3 -m unittest app/test_server.py 2>&1 | tail -1

OUT=Portcullis-Windows
rm -rf "$OUT" "$OUT.zip"
mkdir -p "$OUT/app/ui/img" "$OUT/app/windows"

install -m 644 blocklist.hosts top-domains.txt "$OUT/"
install -m 644 app/tools.json                  "$OUT/app/"
install -m 644 app/ui/index.html app/ui/guide.html "$OUT/app/ui/"
install -m 644 app/ui/img/*.png                "$OUT/app/ui/img/"
install -m 644 windows/panel.ps1 windows/apply-payload.ps1 windows/lib.ps1 \
               windows/guard.ps1 windows/uninstall.ps1 "$OUT/app/windows/"

# Windows wants CRLF in batch and text files.
sed 's/$/\r/' windows/Portcullis.cmd > "$OUT/Portcullis.cmd"
sed 's/$/\r/' windows/README.txt     > "$OUT/README.txt"

(cd "$OUT" && zip -qrX "../$OUT.zip" .)
echo "Built $OUT.zip ($(du -h "$OUT.zip" | cut -f1)) — unsigned; core tested, Windows-only parts unverified."
