# pi-vcc E2E Tests

End-to-end tests for the pi-vcc extension. Tests spawn a real `pi` process with a free LLM (`openrouter/free`) and verify compaction behavior.

## Prerequisites

- `shell-use` CLI installed
- `bun` installed (for running pi)
- `jq` installed (for JSON assertions)
- No API credits needed (uses `openrouter/free`)

## Running Tests

### Real LLM Test (recommended)

```bash
bash e2e/test.sh
```

This test:
1. Opens a shell-use session
2. Starts pi with `openrouter/free` and low threshold (2000 tokens)
3. Sends a task to generate context
4. Waits for compaction to trigger
5. Asserts compaction details and agent continuation

## Test Structure

```
e2e/
├── README.md              # This file
├── test.sh                # Real LLM test (openrouter/free)
├── support/
│   └── assertions.sh      # Shared assertion functions
└── casts/                 # Shell-use recordings (.cast files)
```

## Assertions

The tests verify:

- **Compaction notification**: Screen shows "pi-vcc:.*Compacting" or "kept.*turns"
- **Agent continuation**: Screen shows activity after compaction

Debug output is written to `/tmp/pi-vcc-debug.json` when `PI_VCC_DEBUG=1`.

## Adding New Tests

1. Create a new test file in `e2e/`
2. Source the shared assertions: `source "$(dirname "$0")/support/assertions.sh"`
3. Use `shell-use` to drive the pi session
4. Use the assertion functions to verify behavior

## Recording

Test recordings are saved as `.cast` files in `e2e/casts/`. To view a recording:

```bash
asciinema play e2e/casts/test-threshold.cast
```

## Troubleshooting

### Pi doesn't start

- Check that `shell-use` is installed: `which shell-use`
- Check that `bun` is installed: `which bun`
- Try running pi manually first: `pi -ne -ns -np -nc --model openrouter/free`

### Compaction doesn't trigger

- Check the threshold: `PI_VCC_DEBUG=1` shows debug output
- Lower the threshold in the test (currently 2000 tokens)
- Check if the model is responding: look at screen output

### Test hangs

- Kill the shell-use session: `shell-use --session pivcctest close`
- Kill any lingering pi processes: `pkill -f "pi.*openrouter"`
