#!/usr/bin/env bash
# Shared assertion functions for pi-vcc e2e tests
# Source this file: source "$(dirname "$0")/../support/assertions.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo -e "${GREEN}✓ $1${NC}"
}

fail() {
  FAIL=$((FAIL + 1))
  echo -e "${RED}✗ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Assert compaction was handled by pi-vcc
# Usage: assert_compactor
assert_compactor() {
  local debug_file="/tmp/pi-vcc-debug.json"
  if [ ! -f "$debug_file" ]; then
    fail "Debug file not found: $debug_file"
    return 1
  fi
  local compactor
  compactor=$(jq -r '.compactor // empty' "$debug_file" 2>/dev/null)
  if [ "$compactor" = "pi-vcc" ]; then
    pass "Compactor is pi-vcc"
    return 0
  fi
  # Fallback: check if summaryLength exists (means compaction happened)
  local summary_len
  summary_len=$(jq -r '.summaryLength // 0' "$debug_file" 2>/dev/null)
  if [ "$summary_len" -gt 0 ] 2>/dev/null; then
    pass "Compaction completed (summaryLength: $summary_len)"
    return 0
  fi
  fail "No compaction detected (compactor='$compactor', summaryLength='$summary_len')"
  return 1
}

# Assert compaction reason matches expected
# Usage: assert_compaction_reason "threshold"
assert_compaction_reason() {
  local expected="$1"
  local debug_file="/tmp/pi-vcc-debug.json"
  if [ ! -f "$debug_file" ]; then
    fail "Debug file not found"
    return 1
  fi
  local reason
  reason=$(jq -r '.compaction.reason // .reason // empty' "$debug_file" 2>/dev/null)
  if [ "$reason" = "$expected" ]; then
    pass "Compaction reason is '$expected'"
    return 0
  else
    fail "Compaction reason is '$reason', expected '$expected'"
    return 1
  fi
}

# Assert summary length > 0
# Usage: assert_summary_length
assert_summary_length() {
  local debug_file="/tmp/pi-vcc-debug.json"
  if [ ! -f "$debug_file" ]; then
    fail "Debug file not found"
    return 1
  fi
  local len
  len=$(jq -r '.summaryLength // 0' "$debug_file" 2>/dev/null)
  if [ "$len" -gt 0 ] 2>/dev/null; then
    pass "Summary length is $len chars"
    return 0
  else
    fail "Summary length is $len, expected > 0"
    return 1
  fi
}

# Print test results
# Usage: print_results
print_results() {
  echo ""
  echo "=============================="
  echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
  echo "=============================="
  if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}=== TEST FAILED ===${NC}"
    return 1
  else
    echo -e "${GREEN}=== TEST PASSED ===${NC}"
    return 0
  fi
}

# Clean up debug file
# Usage: cleanup_debug
cleanup_debug() {
  rm -f /tmp/pi-vcc-debug.json
}
