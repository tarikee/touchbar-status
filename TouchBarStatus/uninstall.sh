#!/bin/bash
# Removes TouchBarStatus completely.
set -euo pipefail
LABEL="com.tarik.touchbarstatus"
DEST="$HOME/Applications/TouchBarStatus.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
pkill -f "TouchBarStatus.app/Contents/MacOS/TouchBarStatus" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$DEST"
echo "TouchBarStatus removed."
echo "If its icon lingers in the Control Strip, run: killall ControlStrip"
