#!/bin/bash
# Waits for real keyboard/trackpad input (which lights the Touch Bar),
# then captures it. Usage: verify.sh <out.png> [timeout_sec]
OUT="${1:-touchbar.png}"
TIMEOUT="${2:-90}"
DIR="$(cd "$(dirname "$0")" && pwd)"
idle_ns() { ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/ {print $2; exit}'; }
echo "Waiting up to ${TIMEOUT}s for input (press any key / touch trackpad)..."
for ((i=0; i<TIMEOUT*4; i++)); do
  ns=$(idle_ns)
  if [ -n "$ns" ] && [ "$ns" -lt 1500000000 ]; then
    echo "Input detected (idle ${ns}ns) - capturing"
    "$DIR/capture" "$OUT" 1.2
    exit $?
  fi
  sleep 0.25
done
echo "Timed out - no input seen, Touch Bar likely still dark"
exit 1
