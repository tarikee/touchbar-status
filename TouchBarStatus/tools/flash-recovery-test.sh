#!/bin/bash
# Verifies the Control Strip icon survives a flash: waits for input (which
# lights the panel), switches apps to trigger a flash, then captures well
# after the flash has dismissed.
DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${1:?usage: flash-recovery-test.sh <outdir> [timeout]}"
TIMEOUT="${2:-3000}"
idle_ns() { ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/ {print $2; exit}'; }
for ((i=0; i<TIMEOUT*4; i++)); do
  ns=$(idle_ns)
  if [ -n "$ns" ] && [ "$ns" -lt 1500000000 ]; then
    echo "input detected - running flash recovery test"
    # Two switches, so at least one is a genuine change of focus regardless of
    # what was frontmost. No osascript: that needs Automation permission.
    "$DIR/capture" "$OUTDIR/f%d.png" 9.0 &
    CAP=$!
    sleep 1; open -a Finder
    sleep 3; open -a "Brave Browser"
    wait $CAP                       # frames span both flashes and the settle after
    echo "done"
    exit 0
  fi
  sleep 0.25
done
echo "timed out"; exit 1
