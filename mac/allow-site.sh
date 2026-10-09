#!/bin/bash
# Unblocks one site that was caught by mistake.
#
#   sudo ./scripts/allow-site.sh example.com
#
# Sites that aren't on the adult list are unblocked at once — those are plain
# false positives (a CDN, an image host, a forum swept up by the upstream list).
#
# Sites that ARE on the adult list take a one-hour wait: run it once to ask,
# once more an hour later to confirm. Genuine false positives survive an hour.
# Urges usually don't. Without that, this script would be a one-command way
# round the whole thing.

set -euo pipefail

# Unique temp files: a fixed name in /tmp could be pre-planted as a symlink
# and this script, running as root, would write through it.
T1=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
T2=$(mktemp "${TMPDIR:-/tmp}/portcullis.XXXXXX")
trap 'rm -f "$T1" "$T2"' EXIT

if [[ $EUID -ne 0 ]]; then
  echo "This needs your password. Run it like this:" >&2
  echo "  sudo ./scripts/allow-site.sh example.com" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="/Library/Application Support/Portcullis"
PAYLOAD="$DIR/portcullis.hosts"
PENDING="$DIR/allow-pending"
LOG="/var/log/portcullis-guard.log"
WAIT_MINUTES=60

BEGIN="# >>> portcullis >>>"
END="# <<< portcullis <<<"

ADULT="$DIR/adult-domains.txt"
[[ -f "$ADULT" ]] || ADULT="$HERE/dist/adult-domains.txt"

SITE="${1:-}"
SITE="${SITE#http://}"; SITE="${SITE#https://}"; SITE="${SITE#www.}"; SITE="${SITE%%/*}"
SITE="$(echo "$SITE" | tr '[:upper:]' '[:lower:]')"

if [[ ! "$SITE" =~ ^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$ ]]; then
  echo "Give it a site name, like:  sudo ./scripts/allow-site.sh example.com" >&2
  exit 1
fi

on_adult_list() {
  local d="$1" rest="$1"
  [[ -f "$ADULT" ]] || return 1
  grep -qxF "$d" "$ADULT" && return 0
  while [[ "$rest" == *.*.* ]]; do
    rest="${rest#*.}"
    grep -qxF "$rest" "$ADULT" && return 0
  done
  return 1
}

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null || true; }

# ---- the wait, for adult-list domains only ----------------------------------

if on_adult_list "$SITE"; then
  mkdir -p "$PENDING"; chown root:wheel "$PENDING"; chmod 755 "$PENDING"
  REQ="$PENDING/$SITE"
  now=$(date +%s)

  if [[ ! -f "$REQ" ]]; then
    echo "$now" > "$REQ"; chmod 644 "$REQ"
    say "allow requested for $SITE (on adult list)"
    echo
    echo "$SITE is on the adult list, so this takes an hour."
    echo "  Run the same command again after $(date -r $((now + WAIT_MINUTES * 60)) '+%H:%M') to confirm."
    echo "  Changed your mind: sudo rm '$REQ'"
    exit 0
  fi

  requested=$(cat "$REQ" 2>/dev/null || echo "$now")
  [[ "$requested" =~ ^[0-9]+$ ]] || requested=$now
  elapsed=$(( now - requested ))

  if (( elapsed < WAIT_MINUTES * 60 )); then
    left=$(( (WAIT_MINUTES * 60 - elapsed + 59) / 60 ))
    echo
    echo "Not yet — $left more minutes before $SITE can be unblocked."
    echo "  Cancel: sudo rm '$REQ'"
    exit 1
  fi

  rm -f "$REQ"
  say "allow confirmed for $SITE after the wait"
fi

# ---- unblock ----------------------------------------------------------------

BEFORE=$(grep -c '^0\.0\.0\.0 ' /etc/hosts || true)
cp /etc/hosts "/etc/hosts.portcullis-backup-$(date +%Y%m%d%H%M%S)"

strip_site() {
  awk -v b="$BEGIN" -v e="$END" -v d="$SITE" '
    $0 == b { inside = 1; print; next }
    $0 == e { inside = 0; print; next }
    inside && ($2 == d || substr($2, length($2) - length(d)) == "." d) { next }
    { print }
  ' "$1"
}

strip_site /etc/hosts > "$T1"
install -m 644 -o root -g wheel "$T1" /etc/hosts
rm -f "$T1"

# The guard restores /etc/hosts from its own copy, so that has to match or the
# unblock would be reverted within the second.
if [[ -f "$PAYLOAD" ]]; then
  strip_site "$PAYLOAD" > "$T2"
  install -m 644 -o root -g wheel "$T2" "$PAYLOAD"
  rm -f "$T2"
fi

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

AFTER=$(grep -c '^0\.0\.0\.0 ' /etc/hosts || true)
REMOVED=$(( BEFORE - AFTER ))

echo
if (( REMOVED == 0 )); then
  echo "$SITE wasn't blocked by this list, so something else is stopping it."
else
  say "unblocked $SITE ($REMOVED entries)"
  echo "Unblocked $SITE — $REMOVED entries removed, guard's copy updated to match."
  echo
  echo "To keep it unblocked when the list is rebuilt, add it to allowlist.json:"
  echo "  \"allow\": [\"$SITE\"]"
fi
