#!/bin/bash
# Writes a prepared block into /etc/hosts. Called by the app through the macOS
# administrator prompt, so everything here runs as root.
#
#   sudo bash apply-payload.sh PAYLOAD                     write the block
#   sudo bash apply-payload.sh PAYLOAD --with-guard DIR    and install the watchdog from DIR
#        bash apply-payload.sh PAYLOAD --check             validate only (no root needed)
#
# The payload is written by a process running as you, in a folder you own, so
# root must not trust it. It is copied somewhere only root can touch, then
# checked line by line: the only thing it may contain is "0.0.0.0 <hostname>".
# That way this script can only ever BLOCK names — it can never be used to
# point a real site (your bank, say) at someone else's server.

set -euo pipefail

PAYLOAD="${1:-}"
MODE="${2:-}"
GUARD_SRC="${3:-}"
BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"
GUARD_DIR="/Library/Application Support/Portcullis"
DAEMON="/Library/LaunchDaemons/com.portcullis.guard.plist"
MAX_LINES=500000

fail() { echo "refused: $*" >&2; exit 1; }

[[ -n "$PAYLOAD" && -f "$PAYLOAD" ]] || fail "payload not found"
[[ "$MODE" == "--check" || $EUID -eq 0 ]] || fail "must run as root"

WORK=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
HOSTS_NEW=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$WORK" "$HOSTS_NEW"' EXIT

# Snapshot first, validate the snapshot: the original could change underneath us.
# Carriage returns are dropped here so what's validated is exactly what's written.
tr -d '\r' < "$PAYLOAD" > "$WORK"

# ---------------------------------------------------------------- validation
awk -v b="$BEGIN" -v e="$END" -v max="$MAX_LINES" '
  BEGIN { state = 0; bad = 0 }
  NR > max { print "too many lines" > "/dev/stderr"; exit 2 }
  {
    sub(/\r$/, "")
    if ($0 == b)      { if (state != 0) { print "duplicate begin marker" > "/dev/stderr"; exit 2 } state = 1; next }
    if ($0 == e)      { if (state != 1) { print "end marker out of place" > "/dev/stderr"; exit 2 } state = 2; next }
    if (state != 1)   { if ($0 != "") { print "content outside the markers" > "/dev/stderr"; exit 2 } next }
    if ($0 ~ /^# /)   next
    if ($0 ~ /^0\.0\.0\.0 [a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+$/) next
    printf "line %d is not a block entry: %s\n", NR, substr($0, 1, 80) > "/dev/stderr"
    exit 2
  }
  END { if (state != 2) { print "missing end marker" > "/dev/stderr"; exit 2 } }
' "$WORK" || fail "the block list did not pass validation"

[[ "$MODE" == "--check" ]] && { echo "valid: $(grep -c '^0\.0\.0\.0 ' "$WORK" || true) entries"; exit 0; }

# --------------------------------------------------------------------- write
cp /etc/hosts "/etc/hosts.portcullis-backup-$(date +%Y%m%d%H%M%S)"

awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1 }
  !skip   { print }
  $0 == e { skip = 0 }
' /etc/hosts > "$HOSTS_NEW"
cat "$WORK" >> "$HOSTS_NEW"
install -m 644 -o root -g wheel "$HOSTS_NEW" /etc/hosts

mkdir -p "$GUARD_DIR"; chown root:wheel "$GUARD_DIR"; chmod 755 "$GUARD_DIR"
# The guard restores from this copy, so it has to match or it would revert the change.
install -m 644 -o root -g wheel "$WORK" "$GUARD_DIR/portcullis.hosts"

# ------------------------------------------------------- first-run watchdog
if [[ "$MODE" == "--with-guard" && ! -f "$DAEMON" ]]; then
  [[ -f "$GUARD_SRC/guard.sh" && -f "$GUARD_SRC/com.portcullis.guard.plist" ]] \
    || fail "watchdog files not found in $GUARD_SRC"
  install -m 755 -o root -g wheel "$GUARD_SRC/guard.sh" "$GUARD_DIR/guard.sh"
  install -m 644 -o root -g wheel "$GUARD_SRC/com.portcullis.guard.plist" "$DAEMON"
  launchctl bootout system "$DAEMON" 2>/dev/null || true
  launchctl bootstrap system "$DAEMON"
  echo "watchdog installed"
fi

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

echo "$(grep -c '^0\.0\.0\.0 ' /etc/hosts || true) hosts blocked"
