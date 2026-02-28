#!/usr/bin/env bash
# E2E smoke test: duck say → AI response validation
# Requires: OPENAI_API_KEY or ANTHROPIC_API_KEY set in environment
# Usage: cd cli && npm run build && scripts/e2e-smoke.sh

set -euo pipefail

# Check for API key
if [[ -z "${OPENAI_API_KEY:-}" ]] && [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "SKIP: Set OPENAI_API_KEY or ANTHROPIC_API_KEY to run E2E smoke test"
  exit 0
fi

# Isolated app support dir so test daemon doesn't conflict with real one
TMPDIR_E2E=$(mktemp -d)
export RUBBER_DUCK_APP_SUPPORT="$TMPDIR_E2E"

cleanup() {
  # Kill any daemon we started via the PID file
  local pid_file="${TMPDIR_E2E}/duck-daemon.pid"
  if [[ -f "$pid_file" ]]; then
    local daemon_pid
    daemon_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$daemon_pid" =~ ^[0-9]+$ ]]; then
      kill "$daemon_pid" >/dev/null 2>&1 || true
      sleep 0.1
      kill -9 "$daemon_pid" >/dev/null 2>&1 || true
    fi
  fi

  # Kill attach process if still running
  if [[ -n "${ATTACH_PID:-}" ]]; then
    kill "$ATTACH_PID" >/dev/null 2>&1 || true
  fi

  rm -rf "$TMPDIR_E2E"
}
trap cleanup EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$(dirname "$SCRIPT_DIR")"
CLI_BIN="$CLI_DIR/dist/cli.js"
DAEMON_BIN="$CLI_DIR/dist/daemon.js"

if [[ ! -f "$CLI_BIN" ]]; then
  echo "ERROR: $CLI_BIN not found. Run: cd cli && npm run build"
  exit 1
fi

if [[ ! -f "$DAEMON_BIN" ]]; then
  echo "ERROR: $DAEMON_BIN not found. Run: cd cli && npm run build"
  exit 1
fi

echo "==> Starting daemon..."
node "$DAEMON_BIN" &
DAEMON_PID=$!

# Wait for socket to appear (daemon.sock is the actual socket name)
SOCKET_PATH="$TMPDIR_E2E/daemon.sock"
for i in $(seq 1 20); do
  if [[ -S "$SOCKET_PATH" ]]; then
    break
  fi
  sleep 0.5
done

if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "ERROR: Daemon socket not ready after 10s at $SOCKET_PATH"
  exit 1
fi

echo "==> Daemon ready. Attaching workspace..."
node "$CLI_BIN" "$TMPDIR_E2E" &
ATTACH_PID=$!
sleep 2

echo "==> Sending test message..."
OUTPUT=$(node "$CLI_BIN" say "What is 1+1? Reply with just the number." --no-color 2>&1) || true

kill "$ATTACH_PID" 2>/dev/null || true
unset ATTACH_PID

echo "--- Output ---"
echo "$OUTPUT"
echo "--- End Output ---"

if echo "$OUTPUT" | grep -qE '(^|\s|[^0-9])2([^0-9]|$)'; then
  echo ""
  echo "PASS: E2E smoke test passed — got expected response"
  exit 0
else
  echo ""
  echo "FAIL: Expected to find '2' in response"
  exit 1
fi
