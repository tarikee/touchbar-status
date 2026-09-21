#!/bin/bash
# Ensures TouchBarStatus is running WITH Accessibility.
#
# macOS grants Accessibility per responsible-process: a binary launched from a
# terminal that holds the grant inherits it, while the same binary started by
# launchd does not. So the launchd copy can track focus and show the icon, but
# cannot read window titles or raise windows. This script, run from a shell in
# that terminal, replaces a non-trusted instance with a trusted one.
#
# Add to ~/.zshrc:
#   ~/Desktop/"touchbar status"/TouchBarStatus/tools/ensure-ax-instance.sh &!

APP="$HOME/Applications/TouchBarStatus.app/Contents/MacOS/TouchBarStatus"
PATTERN="TouchBarStatus.app/Contents/MacOS"
[ -x "$APP" ] || exit 0

start() { nohup "$APP" >/dev/null 2>&1 & disown 2>/dev/null; }

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
  trusted=$(defaults read com.tarik.touchbarstatus LastLaunchAXTrusted 2>/dev/null)
  [ "$trusted" = "1" ] && exit 0          # already the good one
  pkill -f "$PATTERN" 2>/dev/null
  sleep 0.5
fi
start
