#!/bin/bash
# Builds TouchBarStatus, installs it to ~/Applications, and registers a
# LaunchAgent so it starts at login.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.tarik.touchbarstatus"
DEST="$HOME/Applications/TouchBarStatus.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

./build.sh

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R build/TouchBarStatus.app "$DEST"
echo "Installed: $DEST"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/Contents/MacOS/TouchBarStatus</string></array>
  <key>RunAtLoad</key><true/>
  <!-- Deliberately false: tools/ensure-ax-instance.sh replaces this instance
       with an Accessibility-inheriting one when a terminal opens. KeepAlive
       would restart this copy and the two would fight. -->
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLISTEOF

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
echo "LaunchAgent loaded: $PLIST"
echo "TouchBarStatus is running and will start automatically at login."
