#!/bin/bash
# Waits for input (which lights the Touch Bar), then opens the picker via
# SIGUSR1 and records it. Verifies the picker's appearance without a tap.
DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${1:?usage: picker-test.sh <outdir> [timeout]}"
TIMEOUT="${2:-3000}"
idle_ns() { ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/ {print $2; exit}'; }
for ((i=0; i<TIMEOUT*4; i++)); do
  ns=$(idle_ns)
  if [ -n "$ns" ] && [ "$ns" -lt 1500000000 ]; then
    echo "input detected - opening picker"
    "$DIR/capture" "$OUTDIR/f%d.png" 8.0 &
    CAP=$!
    sleep 1
    pkill -USR1 -f "TouchBarStatus.app/Contents/MacOS"
    wait $CAP
    echo done
    exit 0
  fi
  sleep 0.25
done
echo "timed out"; exit 1
