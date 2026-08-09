#!/usr/bin/env bash
# E2E test: reuse an existing large session to test compaction loop fix
# Uses openrouter/free (no API credits needed)
set -u

SESSION=pivcctest
WS=/tmp/pi-vcc-e2e-test
EXT="$(cd "$(dirname "$0")/.." && pwd)/index.ts"
SU=shell-use
THRESHOLD=2000  # Low threshold to trigger quickly

# Source assertions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/support/assertions.sh"

# Cleanup on any exit
cleanup() {
  "$SU" --session "$SESSION" close 2>/dev/null
  rm -rf "$WS"
}
trap cleanup EXIT

# Setup
"$SU" --session "$SESSION" close 2>/dev/null
rm -rf "$WS"
mkdir -p "$WS"

# Copy the existing large session
SESSION_FILE="$HOME/.pi/agent/sessions/--var-home-l-git-pi-extensions-forbid-commands--/2026-08-09T04-37-10-723Z_019fe4cf-7bc3-7662-a0c8-a73332093f46.jsonl"
if [ ! -f "$SESSION_FILE" ]; then
  echo "✗ Session file not found: $SESSION_FILE"
  exit 1
fi
cp "$SESSION_FILE" "$WS/test-session.jsonl"
echo "Session file copied ($(du -h "$WS/test-session.jsonl" | cut -f1))"

send() { "$SU" --session "$SESSION" submit "$1" >/dev/null 2>&1; }
txt() { "$SU" --session "$SESSION" text 2>/dev/null; }

# Save recording on exit
CAST_DIR="$SCRIPT_DIR/casts"
mkdir -p "$CAST_DIR"
trap '"$SU" --session "$SESSION" get-recording >"$CAST_DIR/test-existing-session.cast" 2>/dev/null; cleanup' EXIT

"$SU" --session "$SESSION" open --cols 120 --rows 40 2>&1

send "cd $WS"
sleep 1

# Start pi with low threshold via env var, forking the existing session
send "PI_VCC_THRESHOLD=$THRESHOLD PI_VCC_DEBUG=1 pi -ne -ns -np -nc -e $EXT --model openrouter/free --fork $WS/test-session.jsonl"

# Wait for pi to start (max 15s)
echo "Waiting for pi to start..."
if ! "$SU" --session "$SESSION" wait text --regex '[0-9]+\.[0-9]+%/[0-9]+[kmKM]' --timeout 15000 >/dev/null 2>&1; then
  echo "✗ pi did not start"
  echo "Screen output:"
  txt | tail -20
  echo "=== TEST FAILED ==="
  exit 1
fi
echo "✓ pi started"

# Wait for idle
"$SU" --session "$SESSION" wait idle --timeout 10000 >/dev/null 2>&1

# Send a simple message to trigger a turn
echo "Sending message to trigger compaction..."
send "Continue working on the task."

# Wait for compaction notification (max 60s)
echo "Waiting for compaction notification..."
SEEN_COMPACTION=0
for i in $(seq 1 60); do
  sleep 1
  if txt 2>/dev/null | grep -q "pi-vcc:.*Compacting\|pi-vcc:.*threshold\|kept.*turns"; then
    echo "✓ Compaction notification appeared at +${i}s"
    SEEN_COMPACTION=1
    break
  fi
done

if [ "$SEEN_COMPACTION" -eq 0 ]; then
  echo "✗ No compaction after 60s"
  echo "Screen output:"
  txt | tail -30
  echo "=== TEST FAILED ==="
  exit 1
fi

# Wait and check for infinite loop (compaction should NOT re-trigger)
echo ""
echo "Checking for infinite loop (should NOT see multiple compactions)..."
COMPACTION_COUNT=0
for i in $(seq 1 30); do
  sleep 1
  if txt 2>/dev/null | grep -q "pi-vcc:.*Compacting\|pi-vcc:.*threshold"; then
    COMPACTION_COUNT=$((COMPACTION_COUNT + 1))
    echo "  Found compaction #$COMPACTION_COUNT at +${i}s"
    if [ "$COMPACTION_COUNT" -gt 2 ]; then
      echo "✗ INFINITE LOOP DETECTED! ($COMPACTION_COUNT compactions)"
      echo "=== TEST FAILED ==="
      exit 1
    fi
  fi
done

echo ""
echo "Done criteria verified:"
echo "  1. Session loaded successfully"
echo "  2. Compaction triggered (notification appeared)"
if [ "$COMPACTION_COUNT" -le 2 ]; then
  echo "  3. No infinite loop (only $COMPACTION_COUNT compaction(s))"
  echo ""
  echo "=== TEST PASSED ==="
else
  echo "  3. INFINITE LOOP DETECTED!"
  echo "=== TEST FAILED ==="
  exit 1
fi
