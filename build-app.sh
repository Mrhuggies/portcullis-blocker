#!/bin/bash
# Builds Portcullis.app from the source in this folder. Always rebuild rather
# than editing files inside the app, so what ships is exactly what was tested.
#
#   bash build-app.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "Running tests first..."
python3 -m unittest app/test_server.py 2>&1 | tail -1
bash mac/test-apply-payload.sh | tail -1

APP=Portcullis.app
R="$APP/Contents/Resources"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$R/app/ui/img" "$R/mac"

install -m 755 app/launcher.sh            "$APP/Contents/MacOS/Portcullis"
install -m 644 app/server.py app/tools.json "$R/app/"
install -m 644 app/ui/index.html app/ui/guide.html "$R/app/ui/"
install -m 644 app/ui/img/*.png           "$R/app/ui/img/"
install -m 644 blocklist.hosts            "$R/"
install -m 755 mac/apply-payload.sh mac/guard.sh mac/uninstall-hosts.sh "$R/mac/"
install -m 644 mac/com.portcullis.guard.plist mac/Portcullis.mobileconfig "$R/mac/"

# The landing page carries the same guide.
mkdir -p docs/img
install -m 644 app/ui/guide.html docs/
install -m 644 app/ui/img/*.png  docs/img/

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Portcullis</string>
  <key>CFBundleDisplayName</key><string>Portcullis</string>
  <key>CFBundleIdentifier</key><string>app.portcullis.panel</string>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Portcullis</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP" 2>/dev/null
echo "Built $APP ($(du -sh "$APP" | cut -f1)) — ad-hoc signed, not notarised."
