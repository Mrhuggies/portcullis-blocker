#!/bin/bash
# Portcullis.app/Contents/MacOS/Portcullis
#
# Starts the control panel and opens it. The panel lives as long as the app:
# quit Portcullis from the Dock and it stops. Your blocks don't depend on it.

RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
PORT=7378
URL="http://127.0.0.1:$PORT/"
LOG="$HOME/Library/Logs/Portcullis/panel.log"
mkdir -p "$(dirname "$LOG")"

say() {
  /usr/bin/osascript -e "display dialog \"$1\" with title \"Portcullis\" buttons {\"OK\"} default button 1 with icon $2" >/dev/null 2>&1
}

hello() {   # is the thing on our port actually Portcullis?
  /usr/bin/curl -fsS -m 1 "http://127.0.0.1:$PORT/api/hello" 2>/dev/null | /usr/bin/grep -q '"portcullis"'
}

if [[ ! -x /usr/bin/python3 ]] || ! /usr/bin/python3 -c 'import sys' >/dev/null 2>&1; then
  say "Portcullis needs Apple's command line tools. macOS will offer to install them — accept, then open Portcullis again." caution
  /usr/bin/xcode-select --install >/dev/null 2>&1
  exit 1
fi

# Already open? Just bring it up.
if hello; then open "$URL"; exit 0; fi

# Something else on the port: say so rather than opening a page that isn't ours.
if /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  say "Another program is using port $PORT, so the panel can't start. Quit it and try again." stop
  exit 1
fi

/usr/bin/python3 "$RES/app/server.py" >>"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' TERM INT HUP EXIT

for _ in $(seq 1 50); do
  if hello; then open "$URL"; break; fi
  if ! kill -0 $PID 2>/dev/null; then
    say "The panel didn't start. Details are in ~/Library/Logs/Portcullis/panel.log." stop
    exit 1
  fi
  sleep 0.1
done

wait $PID
