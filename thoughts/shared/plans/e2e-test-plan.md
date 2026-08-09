# pi-vcc E2E Test Plan (Updated)

## Overview

Create shell-based end-to-end tests for the pi-vcc extension using **OpenRouter with real LLM** (no mocks). Tests spawn a real `pi` process, drive it via `shell-use`, and assert on compaction behavior.

**No API credits needed** — uses `openrouter/free` (free tier model).

## Current State Analysis

**What exists:**
- 218 unit/integration tests in `tests/` — all pass
- No e2e tests that spawn a real pi process

**What's missing:**
- No test that verifies the full flow: context fills → threshold crossed → compaction fires → agent continues
- No test for manual `/pi-vcc` command in a live session
- No test for `vcc_recall` tool after compaction
- No test for smart-keep behavior in a live session

**Key hooks for assertions (debug mode):**
- `/tmp/pi-vcc-debug.json` — detailed compaction metrics (when `debug: true`)
- Notification text — `pi-vcc: kept N/M turns, ~Xk tok`
- Session JSONL — compaction entries with `details.compactor === "pi-vcc"`
- Agent behavior — auto-continue after threshold compaction

**Auto-handoff pattern (reference):**
- `test.sh` — Real LLM test with `openrouter/free`, shell-use, assertions on debug JSONL + session files

## Desired End State

An `e2e/` directory with real LLM tests:

```
e2e/
├── README.md              # How to run
├── test.sh                # Real LLM test (openrouter/free)
├── support/               # Shared helpers
│   └── assertions.sh      # Common assertion functions
└── casts/                 # Shell-use recordings (gitignored)
```

### Verification:
- `bash e2e/test.sh` passes all assertions (real LLM, ~2-3 min)
- No API credits consumed (uses free tier)

## What We're NOT Doing

- Not using mock APIs — real LLM only
- Not testing specific LLM output quality (that's unit test territory)
- Not testing pi-core itself — only pi-vcc's hooks and commands
- Not testing with paid models

## Implementation Approach

Follow the auto-handoff `test.sh` pattern exactly:
1. Open shell-use session
2. Start pi with `openrouter/free` + pi-vcc extension (low threshold via env var)
3. Send messages to trigger compaction
4. Assert on debug file, notifications, session JSONL
5. Save recording on exit

---

## Phase 1: Real LLM Test (`test.sh`)

### Overview
Full e2e test with `openrouter/free` — same pattern as auto-handoff's `test.sh`.

### Test Flow:
1. Open shell-use session (120x40)
2. `cd` to temp workspace
3. Start pi: `pi -ne -ns -np -nc -e ../index.ts --model openrouter/free`
   - Set env: `PI_VCC_THRESHOLD=2000` (low threshold to trigger quickly)
   - Set env: `PI_VCC_DEBUG=1` (enable debug output)
4. Wait for pi to start (regex: `[0-9]+\.[0-9]+%/[0-9]+[kmKM]`)
5. Wait for idle
6. Send task: "Create a Python todo app with these files: app.py, models.py, storage.py, README.md. Each file should be about 50 lines. Include classes, functions, and docstrings."
7. Poll screen for compaction notification (up to 120s)
8. Assert: notification contains "pi-vcc:.*Compacting" or "kept.*turns"
9. Assert: agent continues after compaction (screen shows more output)
10. Save recording to `casts/`

### Assertions (bash):
```bash
# Compaction notification appears
txt 2>/dev/null | grep -q "pi-vcc:.*Compacting\|pi-vcc:.*threshold\|kept.*turns"

# Agent continued after compaction
SCREEN=$(txt)
echo "$SCREEN" | grep -qiE "(created|wrote|file|app\.py|models\.py|README|storage\.py)"
```

### Success Criteria:
- [ ] Pi starts with `openrouter/free`
- [ ] Compaction triggers (threshold crossed)
- [ ] Compaction notification shown
- [ ] Agent continues after compaction
- [ ] Recording saved to `casts/`

---

## Phase 2: Manual `/pi-vcc` Command Test

### Overview
Verify that `/pi-vcc` triggers compaction on demand.

### Test Flow:
1. Start pi with high threshold (so auto doesn't trigger)
2. Send a few messages
3. Send `/pi-vcc`
4. Assert: compaction fires
5. Assert: stats notification shown

### Assertions:
```bash
shell-use wait text "kept.*turns" --timeout 10000
```

### Success Criteria:
- [ ] `/pi-vcc` triggers compaction
- [ ] Stats notification shown

---

## Phase 3: Config Toggle Tests

### Overview
Verify pi-vcc config settings are respected in live sessions.

### Sub-tests:

#### 3a: `continueAfterThresholdCompact: false`
- Start pi with low threshold + this config
- Trigger compaction
- Assert: agent does NOT continue (no auto-continue message)

#### 3b: `overrideDefaultCompaction: false`
- Start pi with this config
- Send `/compact` (not `/pi-vcc`)
- Assert: pi-vcc does NOT handle it (falls through to pi-core)

### Success Criteria:
- [ ] Each config toggle produces expected behavior

---

## File Structure

```
e2e/
├── README.md
├── test.sh              # Real LLM (openrouter/free)
├── support/
│   └── assertions.sh    # Shared helpers
└── casts/               # .cast recordings (gitignored)
```

## Testing Strategy

### What each test verifies:
| Test | LLM | Time | Key Assertion |
|---|---|---|---|
| `test.sh` | `openrouter/free` | ~2-3 min | Full flow: threshold → compaction → continue |

### Running:
```bash
bash e2e/test.sh           # Real LLM test
```

### Prerequisites:
- `shell-use` CLI installed
- `bun` installed
- `jq` installed
- No API credits needed (uses openrouter/free)

## Performance Considerations

- Real LLM test: ~2-3 min (depends on openrouter/free latency)
- Low threshold (2000 tokens) = fewer messages to trigger compaction

## References

- Auto-handoff e2e pattern: `/var/home/l/git/agent-stuff/pi-ext/auto-handoff/e2e/test.sh`
- shell-use skill: `/var/home/l/.pi/agent/skills/shell-use/SKILL.md`
- pi-vcc config: `~/.pi/agent/pi-vcc-config.json`
- pi-vcc debug output: `/tmp/pi-vcc-debug.json`
