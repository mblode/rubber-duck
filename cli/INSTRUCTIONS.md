# Duck CLI — Quick Reference

## Basic Workflow

```bash
# 1. Attach/resume workspace and stream events
duck /path/to/project

# 2. Send prompts (same or another terminal)
duck say "list all files in src/"
duck say "explain the main entry point"
```

## Common Commands

| Command | Description |
|---|---|
| `duck [path]` | Attach/resume directory and stream active session |
| `duck say <msg>` | Send prompt and stream response |
| `duck sessions` | List all sessions |
| `duck doctor` | Health check |

## Troubleshooting

### Nothing happens after `duck`

The Pi process may be stale or stuck. Reset it:

```bash
# Kill the daemon (it auto-restarts on next command)
duck doctor                    # Note the daemon PID
kill <daemon-pid>

# Or kill all duck processes and start fresh
pkill -f duck-daemon
duck .
```

### `duck say` hangs after showing the prompt

The Pi process accepted the prompt but isn't responding. Common causes:

1. **API key issue** — Check `duck doctor` for provider status
2. **Stale session** — Create a new one:
   ```bash
   # start fresh stream from your repo root
   duck .
   duck say "hello"
   ```

### Cycling between "Thinking..." and "Listening..."

Fixed in latest build. The renderer now debounces rapid status changes (200ms window). Rebuild if needed:

```bash
cd cli && npm run build
```

### Daemon won't start or socket errors

```bash
# Check for stale socket/PID files
ls ~/Library/Application\ Support/RubberDuck/
# Or in sandbox:
ls ~/Library/Containers/co.blode.rubber-duck/Data/Library/Application\ Support/RubberDuck/

# Remove stale files and restart
rm -f /var/folders/*/*/T/rubber-duck-*.sock
pkill -f duck-daemon
duck .
```

### Check daemon logs

```bash
# Non-sandboxed:
tail -f ~/Library/Application\ Support/RubberDuck/duck-daemon.log

# Sandboxed (from Rubber Duck.app):
tail -f ~/Library/Containers/co.blode.rubber-duck/Data/Library/Application\ Support/RubberDuck/duck-daemon.log
```

### Run daemon in foreground for debugging

```bash
pkill -f duck-daemon
cd /path/to/rubber-duck/cli
node dist/daemon.js --verbose
```

## Session Files

Pi session transcripts are stored as JSONL:

```
~/Library/Application Support/RubberDuck/pi-sessions/*.jsonl
# or sandboxed:
~/Library/Containers/co.blode.rubber-duck/Data/Library/Application Support/RubberDuck/pi-sessions/
```

## Environment Variables

| Variable | Purpose |
|---|---|
| `RUBBER_DUCK_PI_BINARY` | Override Pi binary path |
| `OPENAI_API_KEY` | OpenAI API key |
| `ANTHROPIC_API_KEY` | Anthropic API key |

## E2E Testing

End-to-end tests validate real API calls. They are skipped automatically when API keys are absent.

### CLI Daemon Integration Test

Requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`:

```bash
# Run from cli/ directory
OPENAI_API_KEY=sk-... npm test -- e2e
# or
ANTHROPIC_API_KEY=sk-ant-... npm test -- e2e
```

### CLI Shell Smoke Test

```bash
cd cli && npm run build
ANTHROPIC_API_KEY=sk-ant-... scripts/e2e-smoke.sh
```

### Swift Realtime E2E Test

Requires an OpenAI API key in `/tmp/rubber-duck-live-realtime-test`:

```bash
# Line 1: API key. Line 2 (optional): model override
echo "sk-..." > /tmp/rubber-duck-live-realtime-test
# Optionally override model:
echo "gpt-4o-realtime-preview" >> /tmp/rubber-duck-live-realtime-test

make e2e-swift
```

Tests skip gracefully with `XCTSkip` when the flag file is absent.

## Build

```bash
cd cli
npm install
npm run build          # Build CLI
npm run typecheck      # Type check
npm run lint           # Lint
```
