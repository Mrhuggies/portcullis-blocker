#!/bin/bash
# Installs the watchdog that keeps the /etc/hosts block intact.
#
#   sudo ./scripts/install-guard.sh
#
# Re-run this after regenerating the hosts file (e.g. after editing
# allowlist.json) so the guard restores from the current version.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/install-guard.sh" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="/Library/Application Support/Portcullis"
DAEMON="/Library/LaunchDaemons/com.portcullis.guard.plist"

[[ -f "$HERE/dist/portcullis.hosts" ]] || {
  echo "Missing dist/portcullis.hosts — run: node scripts/make-hosts.mjs" >&2; exit 1; }

mkdir -p "$DIR"
chown root:wheel "$DIR"; chmod 755 "$DIR"

install -m 644 -o root -g wheel "$HERE/dist/portcullis.hosts" "$DIR/portcullis.hosts"
if [[ -f "$HERE/dist/adult-domains.txt" ]]; then
  install -m 644 -o root -g wheel "$HERE/dist/adult-domains.txt" "$DIR/adult-domains.txt"
fi
install -m 755 -o root -g wheel "$HERE/scripts/guard.sh"      "$DIR/guard.sh"
if [[ -f "$HERE/dist/Portcullis.mobileconfig" ]]; then
  install -m 644 -o root -g wheel "$HERE/dist/Portcullis.mobileconfig" "$DIR/Portcullis.mobileconfig"
fi

install -m 644 -o root -g wheel "$HERE/scripts/com.portcullis.guard.plist" "$DAEMON"

launchctl bootout system "$DAEMON" 2>/dev/null || true
launchctl bootstrap system "$DAEMON"

sleep 1
echo
if launchctl print system/com.portcullis.guard >/dev/null 2>&1; then
  echo "Guard installed and running."
  echo "  payload : $DIR/portcullis.hosts"
  echo "  watches : /etc/hosts (plus an hourly check)"
  echo "  log     : /var/log/portcullis-guard.log"
else
  echo "Guard did not start — check /var/log/portcullis-guard.log" >&2
  exit 1
fi
