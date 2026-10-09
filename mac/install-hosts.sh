#!/bin/bash
# Appends the Portcullis block to /etc/hosts, between markers so it can be
# removed cleanly later. Idempotent — safe to re-run after regenerating.
#
#   sudo ./scripts/install-hosts.sh

set -euo pipefail

# Unique temp files: a fixed name in /tmp could be pre-planted as a symlink
# and this script, running as root, would write through it.
T1=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$T1"' EXIT

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/install-hosts.sh" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/dist/portcullis.hosts"
BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"

[[ -f "$SRC" ]] || { echo "Missing dist/portcullis.hosts — run: node scripts/make-hosts.mjs" >&2; exit 1; }

BACKUP="/etc/hosts.portcullis-backup-$(date +%Y%m%d%H%M%S)"
cp /etc/hosts "$BACKUP"
echo "Backed up /etc/hosts -> $BACKUP"

# Drop any previous block, keeping whatever else lives in the file.
awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1 }
  !skip   { print }
  $0 == e { skip = 0 }
' /etc/hosts > "$T1"

cat "$SRC" >> "$T1"
install -m 644 -o root -g wheel "$T1" /etc/hosts
rm -f "$T1"

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# Keep the guard's copy in step, or it would restore the previous version.
GUARD_DIR="/Library/Application Support/Portcullis"
if [[ -f "$GUARD_DIR/portcullis.hosts" ]]; then
  install -m 644 -o root -g wheel "$SRC" "$GUARD_DIR/portcullis.hosts"
  if [[ -f "$HERE/dist/adult-domains.txt" ]]; then
    install -m 644 -o root -g wheel "$HERE/dist/adult-domains.txt" "$GUARD_DIR/adult-domains.txt"
  fi
  echo "Refreshed the guard's copy of the block list."
fi

COUNT=$(grep -c '^0\.0\.0\.0 ' /etc/hosts || true)
echo "Installed. /etc/hosts now blocks $COUNT hosts."
echo
echo "Verify:  dig +short x.com @127.0.0.1 >/dev/null; ping -c1 x.com"
echo "         (should resolve to 0.0.0.0)"
