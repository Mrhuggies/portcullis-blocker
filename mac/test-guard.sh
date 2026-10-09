#!/bin/bash
# Proves the guard works by removing the block and watching it come back.
#
#   sudo ./scripts/test-guard.sh
#
# If the guard does not restore it within 10 seconds, this puts it back itself,
# so a failed test never leaves the Mac unprotected.

set -uo pipefail

# Unique temp files: a fixed name in /tmp could be pre-planted as a symlink
# and this script, running as root, would write through it.
T1=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$T1"' EXIT

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/test-guard.sh" >&2
  exit 1
fi

BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"
DIR="/Library/Application Support/Portcullis"
SAFETY=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")

# grep -c exits 1 when the count is zero, so take the number and ignore status.
count() { local n; n=$(grep -c '^0\.0\.0\.0 ' /etc/hosts 2>/dev/null) || n=0; echo "${n:-0}"; }

if ! launchctl print system/com.portcullis.guard >/dev/null 2>&1; then
  echo "The guard isn't running. Install it first:  sudo ./scripts/install-guard.sh" >&2
  exit 1
fi

cp /etc/hosts "$SAFETY"
echo "before   : $(count) blocked"

awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1 }
  skip == 0 { print }
  $0 == e { skip = 0 }
' /etc/hosts > "$T1"
install -m 644 -o root -g wheel "$T1" /etc/hosts
rm -f "$T1"

echo "tampered : $(count) blocked   <- block removed by hand"

for i in $(seq 1 10); do
  sleep 1
  n=$(count)
  if [[ "$n" -gt 0 ]]; then
    echo "restored : $n blocked   <- guard stepped in after ${i}s"
    rm -f "$SAFETY"
    echo
    echo "PASS — the block heals itself."
    [[ -f "$DIR/removal-requested" ]] &&
      echo "Note: a removal request is still pending. Cancel it with:" &&
      echo "  sudo ./scripts/uninstall-hosts.sh --cancel"
    exit 0
  fi
done

install -m 644 -o root -g wheel "$SAFETY" /etc/hosts
rm -f "$SAFETY"
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

echo
echo "FAIL — the guard did not restore it within 10s. I put the block back myself."
echo "Check the log:  sudo tail -20 /var/log/portcullis-guard.log"
exit 1
