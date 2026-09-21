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
[ -x "$APP" ] || exit 0

# Match the executable's exact command line, never a substring: any shell whose
# command line merely mentions this path (a script containing it, an editor, a
# grep) matches a loose `pgrep -f` and would be killed or signalled by mistake.
match()  { pgrep -fx "$APP"; }
killall_() { pkill -fx "$APP"; }

start() { nohup "$APP" >/dev/null 2>&1 & disown 2>/dev/null; }

if match >/dev/null 2>&1; then
  trusted=$(defaults read com.tarik.touchbarstatus LastLaunchAXTrusted 2>/dev/null)
  [ "$trusted" = "1" ] && exit 0          # already the good one
  killall_ 2>/dev/null
  sleep 0.5
fi
start
