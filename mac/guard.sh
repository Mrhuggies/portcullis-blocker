#!/bin/bash
# Keeps the /etc/hosts block intact. Run by launchd whenever /etc/hosts changes,
# and hourly as a backstop. Installed copy lives in /Library; this file in the
# repo is the source.
#
# It stands down once a removal request has matured, so uninstall-hosts.sh can
# do its job after the waiting period without a fight.

set -uo pipefail

# Unique temp files: a fixed name in /tmp could be pre-planted as a symlink
# and this script, running as root, would write through it.
T1=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$T1"' EXIT

DIR="/Library/Application Support/Portcullis"
SRC="$DIR/portcullis.hosts"
PROFILE="$DIR/Portcullis.mobileconfig"
REQ="$DIR/removal-requested"
LOG="/var/log/portcullis-guard.log"
WAIT_HOURS=48

BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# Notifications and GUI actions have to run as the logged-in user, not root.
as_user() {
  local uid user
  uid=$(stat -f %u /dev/console 2>/dev/null) || return 0
  user=$(stat -f %Su /dev/console 2>/dev/null) || return 0
  [[ "$user" == "root" || -z "$user" ]] && return 0
  launchctl asuser "$uid" sudo -u "$user" "$@" >/dev/null 2>&1 || true
}

notify() {
  as_user osascript -e "display notification \"$1\" with title \"Portcullis\""
}

[[ -f "$SRC" ]] || { say "payload missing at $SRC — nothing to restore from"; exit 0; }

# A matured removal request means the user has waited it out. Stay out of the way.
if [[ -f "$REQ" ]]; then
  requested=$(cat "$REQ" 2>/dev/null || echo 0)
  if [[ "$requested" =~ ^[0-9]+$ ]] && (( $(date +%s) - requested >= WAIT_HOURS * 3600 )); then
    exit 0
  fi
fi

# ---- hosts block ------------------------------------------------------------

current=$(awk -v b="$BEGIN" -v e="$END" '$0==b{p=1} p{print} $0==e{p=0}' /etc/hosts 2>/dev/null)

if [[ -z "$current" ]] || ! diff -q <(printf '%s\n' "$current") "$SRC" >/dev/null 2>&1; then
  cp /etc/hosts "/etc/hosts.portcullis-guard-$(date +%Y%m%d%H%M%S)" 2>/dev/null

  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1 }
    !skip   { print }
    $0 == e { skip = 0 }
  ' /etc/hosts > "$T1"

  cat "$SRC" >> "$T1"
  install -m 644 -o root -g wheel "$T1" /etc/hosts
  rm -f "$T1"

  dscacheutil -flushcache 2>/dev/null
  killall -HUP mDNSResponder 2>/dev/null

  count=$(grep -c '^0\.0\.0\.0 ' /etc/hosts)
  say "restored hosts block ($count entries)"
  notify "The block was removed. It has been put back."
fi

# ---- chrome profile ---------------------------------------------------------
# macOS will not let a script install a configuration profile — a person has to
# approve it in System Settings. The most this can do is put it back in the
# queue and say so.

if [[ ! -f "/Library/Managed Preferences/com.google.Chrome.plist" && -f "$PROFILE" ]]; then
  stamp="$DIR/.profile-nagged"
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  if (( $(date +%s) - last > 3600 )); then
    date +%s > "$stamp"
    as_user open "$PROFILE"
    notify "The Chrome profile is missing. It is waiting in System Settings > Device Management."
    say "chrome profile missing — re-staged for approval"
  fi
fi

exit 0
