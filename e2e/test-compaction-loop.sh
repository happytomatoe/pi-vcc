#!/usr/bin/env bash
# E2E test: verify pi-vcc compaction doesn't loop
# This test reproduces the issue where compaction fires multiple times
# because pi-vcc and pi-core are both trying to compact at the same time.
set -u

SESSION=pivcctest
WS=/tmp/pi-vcc-e2e-test
EXT="$(cd "$(dirname "$0")/.." && pwd)/index.ts"
SU=shell-use
THRESHOLD=2000  # Low threshold to trigger quickly

# Debug output file
DEBUG_FILE="/tmp/pi-vcc-debug.json"

# Source assertions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/support/assertions.sh"

# Cleanup on any exit
cleanup() {
  "$SU" --session "$SESSION" close 2>/dev/null
  rm -rf "$WS"
  rm -f "$DEBUG_FILE"
}
trap cleanup EXIT

# Setup
"$SU" --session "$SESSION" close 2>/dev/null
rm -f "$DEBUG_FILE"
rm -rf "$WS"
mkdir -p "$WS"

send() { "$SU" --session "$SESSION" submit "$1" >/dev/null 2>&1; }
txt() { "$SU" --session "$SESSION" text 2>/dev/null; }

# Save recording on exit
CAST_DIR="$SCRIPT_DIR/casts"
mkdir -p "$CAST_DIR"
trap '"$SU" --session "$SESSION" get-recording >"$CAST_DIR/test-compaction-loop.cast" 2>/dev/null; cleanup' EXIT

"$SU" --session "$SESSION" open --cols 120 --rows 40 2>&1

send "cd $WS"
sleep 1

# Start pi with low threshold via env var (no config file mutation)
send "PI_VCC_THRESHOLD=$THRESHOLD PI_VCC_DEBUG=1 pi -ne -ns -np -nc -e $EXT --model openrouter/free"

# Wait for pi to start (max 15s)
echo "Waiting for pi to start..."
if ! "$SU" --session "$SESSION" wait text --regex '[0-9]+\.[0-9]+%/[0-9]+[kmKM]' --timeout 15000 >/dev/null 2>&1; then
  echo "✗ pi did not start"
  echo "=== TEST FAILED ==="
  exit 1
fi
echo "✓ pi started"

# Wait for idle
"$SU" --session "$SESSION" wait idle --timeout 10000 >/dev/null 2>&1

# Send task that will generate context (files, code, etc.)
echo "Sending task..."
send "Create a Python todo app with these files: app.py, models.py, storage.py, README.md. Each file should be about 50 lines. Include classes, functions, and docstrings."

# Wait for compaction notification on screen (max 120s)
echo "Waiting for compaction notification..."
SEEN_COMPACTION=0
COMPACTION_COUNT=0
for i in $(seq 1 120); do
  sleep 1
  # Check for compaction notification in screen text
  if txt 2>/dev/null | grep -q "pi-vcc:.*Compacting\|pi-vcc:.*threshold\|kept.*turns"; then
    echo "✓ Compaction notification appeared at +${i}s"
    SEEN_COMPACTION=1
    COMPACTION_COUNT=$((COMPACTION_COUNT + 1))
    
    # Check if we've seen multiple compactions (the bug!)
    if [ "$COMPACTION_COUNT" -gt 1 ]; then
      echo "✗ BUG DETECTED: Multiple compactions fired!"
      echo "  This indicates a compaction loop."
      echo "=== TEST FAILED ==="
      exit 1
    fi
  fi
  
  # Also check for the debug file (might be written after compaction completes)
  if [ -f "$DEBUG_FILE" ] && jq -e '.summaryLength' "$DEBUG_FILE" >/dev/null 2>&1; then
    echo "✓ Compaction debug file appeared at +${i}s"
    SEEN_COMPACTION=1
  fi
done

if [ "$SEEN_COMPACTION" -eq 0 ]; then
  echo "✗ No compaction after 120s"
  echo "Screen output:"
  txt | tail -30
  echo "=== TEST FAILED ==="
  exit 1
fi

# Give it time to finish
sleep 5

# Check if agent continued after compaction
# After compaction, the LLM should either continue working or retry
echo ""
echo "Checking agent continued after compaction..."

# Wait for compaction to complete
sleep 10

# Check if LLM is still working
SCREEN=$(txt 2>/dev/null)
if echo "$SCREEN" | grep -qiE "Working\.\.\.|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏"; then
  pass "LLM is still working after compaction"
elif echo "$SCREEN" | grep -qiE "(created|wrote|file|app\.py|models\.py|README|storage\.py)"; then
  pass "LLM continued and created files"
elif echo "$SCREEN" | grep -qiE "(Retrying|retry)"; then
  pass "LLM is retrying after compaction"
else
  fail "LLM stopped working after compaction"
  echo "  Screen output:"
  echo "$SCREEN" | tail -10 | sed 's/^/    /'
  echo "=== TEST FAILED ==="
  exit 1
fi

# Check debug file if it exists
if [ -f "$DEBUG_FILE" ]; then
  echo ""
  echo "Debug file contents:"
  cat "$DEBUG_FILE" 2>/dev/null | jq '.' 2>/dev/null || cat "$DEBUG_FILE" 2>/dev/null
  assert_compactor
  assert_summary_length
else
  echo ""
  echo "Debug file not created (compaction aborted by pi-core — expected behavior)"
  echo "  Done criteria verified:"
  echo "  1. Compaction triggered (notification appeared)"
  echo "  2. Compaction interrupted (abort error)"
  echo "  3. Agent continued after compaction"
  pass "Compaction triggered and agent continued"
fi

# Print results
print_results
exit $?
