#!/bin/bash
# Waits for real HID input (which lights the Touch Bar), then drives a couple
# of app switches while recording the panel, to capture the name flash.
DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${1:?usage: demo-capture.sh <outdir> [timeout]}"
TIMEOUT="${2:-600}"
idle_ns() { ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/ {print $2; exit}'; }
for ((i=0; i<TIMEOUT*4; i++)); do
  ns=$(idle_ns)
  if [ -n "$ns" ] && [ "$ns" -lt 1500000000 ]; then
    echo "input detected - recording"
    "$DIR/capture" "$OUTDIR/f%d.png" 10.0 &
    CAP=$!
    sleep 1; open -a Finder
    sleep 2; open -a "Brave Browser"
    sleep 2; open -a Finder
    wait $CAP
    echo "demo capture complete"
    exit 0
  fi
  sleep 0.25
done
echo "timed out waiting for input"
exit 1
