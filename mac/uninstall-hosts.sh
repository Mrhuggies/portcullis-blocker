#!/bin/bash
# Removes the Portcullis block from /etc/hosts — after a waiting period.
#
#   sudo bash uninstall-hosts.sh            first run: files the request
#   sudo bash uninstall-hosts.sh            after 48h: actually removes it
#   sudo bash uninstall-hosts.sh --cancel   calls the whole thing off
#
# Inside the app it lives at
#   /Applications/Portcullis.app/Contents/Resources/mac/uninstall-hosts.sh
#
# The wait is the point. If you need a single site unblocked rather than the
# lot, use allow-site.sh instead — that has no waiting period.

set -euo pipefail

# Unique temp files: a fixed name in /tmp could be pre-planted as a symlink
# and this script, running as root, would write through it.
T1=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$T1"' EXIT

ME="sudo bash $0"            # how to run this again, wherever it lives

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: $ME" >&2
  exit 1
fi

DIR="/Library/Application Support/Portcullis"
REQ="$DIR/removal-requested"
DAEMON="/Library/LaunchDaemons/com.portcullis.guard.plist"
WAIT_HOURS=48

BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"

human() {  # seconds -> "41h 12m"
  printf '%dh %dm' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 ))
}

if [[ "${1:-}" == "--cancel" ]]; then
  rm -f "$REQ"
  echo "Removal cancelled. The block stays as it is."
  exit 0
fi

if ! grep -qF "$BEGIN" /etc/hosts; then
  echo "Nothing to remove — the block isn't installed."
  rm -f "$REQ"
  exit 0
fi

now=$(date +%s)

# ---- first run: file the request -------------------------------------------
if [[ ! -f "$REQ" ]]; then
  mkdir -p "$DIR"; chown root:wheel "$DIR"; chmod 755 "$DIR"
  echo "$now" > "$REQ"
  chown root:wheel "$REQ"; chmod 644 "$REQ"
  ready=$(( now + WAIT_HOURS * 3600 ))
  echo
  echo "Removal requested. Nothing has been removed yet."
  echo "  Come back after $(date -r "$ready" '+%a %e %b, %H:%M') and run this again to confirm."
  echo "  Changed your mind: $ME --cancel"
  exit 0
fi

# ---- later runs -------------------------------------------------------------
requested=$(cat "$REQ" 2>/dev/null || echo 0)
[[ "$requested" =~ ^[0-9]+$ ]] || requested=$now
elapsed=$(( now - requested ))

if (( elapsed < WAIT_HOURS * 3600 )); then
  echo
  echo "Not yet. $(human $(( WAIT_HOURS * 3600 - elapsed ))) left of the $WAIT_HOURS-hour wait."
  echo "  Requested  : $(date -r "$requested" '+%a %e %b, %H:%M')"
  echo "  Unlocks    : $(date -r "$(( requested + WAIT_HOURS * 3600 ))" '+%a %e %b, %H:%M')"
  echo "  Cancel     : $ME --cancel"
  exit 1
fi

# The guard would only put it straight back. Remove it for good, not just for
# now: a launch file left behind would start it again at the next restart, and
# with the request gone it would restore the block.
launchctl bootout system "$DAEMON" 2>/dev/null || true
rm -f "$DAEMON" "$DIR/guard.sh" "$DIR/portcullis.hosts"

cp /etc/hosts "/etc/hosts.portcullis-backup-$(date +%Y%m%d%H%M%S)"

awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1 }
  !skip   { print }
  $0 == e { skip = 0 }
' /etc/hosts > "$T1"

install -m 644 -o root -g wheel "$T1" /etc/hosts
rm -f "$T1" "$REQ"

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

echo "Removed. /etc/hosts restored, and the watchdog has been removed."
echo "The Chrome profile is separate: System Settings > General > Device Management."
