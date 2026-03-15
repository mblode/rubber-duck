#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_DIR="$ROOT_DIR/cli"
IOS_PROJECT="$ROOT_DIR/apps/ios/RubberDuckIOS.xcodeproj"
IOS_SCHEME="RubberDuckIOS"
DERIVED_DATA="${RUBBER_DUCK_IOS_E2E_DERIVED_DATA:-/tmp/rubber-duck-ios-e2e-build}"
SIMULATOR_NAME="${RUBBER_DUCK_IOS_SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_OS="${RUBBER_DUCK_IOS_SIMULATOR_OS:-26.2}"
REMOTE_BIND_HOST="${RUBBER_DUCK_IOS_REMOTE_BIND_HOST:-127.0.0.1}"
HOST_NAME="${RUBBER_DUCK_IOS_TEST_HOST_NAME:-UI Test Mac}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required for live iOS E2E." >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d /tmp/rubber-duck-ios-e2e.XXXXXX)"
APP_SUPPORT="$TEMP_ROOT/app-support"
WORKSPACE="$TEMP_ROOT/workspace"
DAEMON_LOG="$TEMP_ROOT/daemon.log"
ATTACH_LOG="$TEMP_ROOT/attach.log"
CONFIG_JSON="$TEMP_ROOT/ios-ui-test-config.json"
CONFIG_SERVER_PORT="${RUBBER_DUCK_IOS_UI_TEST_CONFIG_PORT:-43112}"
mkdir -p "$APP_SUPPORT" "$WORKSPACE"

DAEMON_PID=""
CONFIG_SERVER_PID=""

cleanup() {
  if [[ -n "${CONFIG_SERVER_PID:-}" ]] && kill -0 "$CONFIG_SERVER_PID" >/dev/null 2>&1; then
    kill "$CONFIG_SERVER_PID" >/dev/null 2>&1 || true
    wait "$CONFIG_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${DAEMON_PID:-}" ]] && kill -0 "$DAEMON_PID" >/dev/null 2>&1; then
    kill "$DAEMON_PID" >/dev/null 2>&1 || true
    wait "$DAEMON_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

wait_for_socket() {
  local socket_path="$1"
  for _ in $(seq 1 50); do
    if [[ -S "$socket_path" ]]; then
      return 0
    fi
    sleep 0.2
  done
  echo "Daemon socket did not appear at $socket_path" >&2
  return 1
}

read_json_field() {
  local field="$1"
  node -e '
    let input = "";
    process.stdin.on("data", (chunk) => { input += chunk; });
    process.stdin.on("end", () => {
      const data = JSON.parse(input);
      const value = process.argv[1]
        .split(".")
        .reduce((current, key) => (current == null ? undefined : current[key]), data);
      if (value == null) {
        process.exit(1);
      }
      process.stdout.write(String(value));
    });
  ' "$field"
}

find_available_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_for_http() {
  local url="$1"

  for _ in $(seq 1 50); do
    if curl --silent --fail "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "Timed out waiting for $url" >&2
  return 1
}

SENTINEL="ui-e2e-$(date +%s)"
PROMPT="Read the file ui-test.txt and reply with its exact contents only."
printf '%s\n' "$SENTINEL" > "$WORKSPACE/ui-test.txt"

echo "Building CLI..."
(cd "$CLI_DIR" && npm run build)

echo "Starting isolated daemon..."
RUBBER_DUCK_APP_SUPPORT="$APP_SUPPORT" \
  node "$CLI_DIR/dist/daemon.js" --verbose >"$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!

wait_for_socket "$APP_SUPPORT/daemon.sock"

echo "Attaching workspace..."
(
  cd "$CLI_DIR"
  RUBBER_DUCK_APP_SUPPORT="$APP_SUPPORT" \
    node dist/cli.js "$WORKSPACE" >"$ATTACH_LOG" 2>&1 &
  local_attach_pid=$!
  sleep 2
  kill -INT "$local_attach_pid" >/dev/null 2>&1 || true
  wait "$local_attach_pid" >/dev/null 2>&1 || true
)

REMOTE_BIND_PORT="${RUBBER_DUCK_IOS_REMOTE_PORT:-$(find_available_port)}"

echo "Enabling isolated remote control on $REMOTE_BIND_HOST:$REMOTE_BIND_PORT..."
ENABLE_JSON="$(
  cd "$CLI_DIR" && \
  RUBBER_DUCK_APP_SUPPORT="$APP_SUPPORT" \
    node dist/cli.js remote enable --host "$REMOTE_BIND_HOST" --port "$REMOTE_BIND_PORT" --json
)"

if [[ "$(printf '%s' "$ENABLE_JSON" | read_json_field status.listening)" != "true" ]]; then
  echo "Isolated remote daemon failed to start: $(printf '%s' "$ENABLE_JSON" | read_json_field status.lastError)" >&2
  exit 1
fi

REMOTE_PUBLIC_URL="${RUBBER_DUCK_IOS_REMOTE_URL:-$(printf '%s' "$ENABLE_JSON" | read_json_field status.httpUrl)}"

echo "Preparing remote pairing payload..."
PAIR_JSON="$(
  cd "$CLI_DIR" && \
  RUBBER_DUCK_APP_SUPPORT="$APP_SUPPORT" \
    node dist/cli.js remote pair --public-url "$REMOTE_PUBLIC_URL" --json
)"

REMOTE_URL="$(printf '%s' "$PAIR_JSON" | read_json_field publicUrl)"
REMOTE_TOKEN="$(printf '%s' "$PAIR_JSON" | read_json_field authToken)"
EXPECTED_SESSION_NAME="$(cat "$APP_SUPPORT/metadata.json" | read_json_field sessions.0.name)"

cat > "$CONFIG_JSON" <<EOF
{"remoteURL":"$REMOTE_URL","remoteToken":"$REMOTE_TOKEN","prompt":"$PROMPT","expectedHostName":"$HOST_NAME","expectedSessionName":"$EXPECTED_SESSION_NAME","expectedAssistantText":"$SENTINEL"}
EOF

echo "Starting localhost UI-test config server..."
python3 -m http.server "$CONFIG_SERVER_PORT" --bind 127.0.0.1 --directory "$TEMP_ROOT" >/dev/null 2>&1 &
CONFIG_SERVER_PID=$!
wait_for_http "http://127.0.0.1:$CONFIG_SERVER_PORT/ios-ui-test-config.json"

echo "Running live iOS UI test..."

run_live_ui_test() {
  local log_path="$TEMP_ROOT/live-ui-test.log"
  set +e
  xcodebuild \
    -project "$IOS_PROJECT" \
    -scheme "$IOS_SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=$SIMULATOR_NAME,OS=$SIMULATOR_OS" \
    -sdk iphonesimulator \
    -derivedDataPath "$DERIVED_DATA" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    SDKROOT=iphonesimulator \
    -only-testing:RubberDuckIOSUITests/RubberDuckIOSUITests/testTypedPromptRemoteControlFlow \
    test 2>&1 | tee "$log_path"
  local xcodebuild_status=${PIPESTATUS[0]}
  set -e

  if [[ "$xcodebuild_status" -ne 0 ]]; then
    return "$xcodebuild_status"
  fi

  if grep -Eq "Test skipped|with [0-9]+ test skipped" "$log_path"; then
    echo "Live iOS E2E skipped unexpectedly." >&2
    return 1
  fi
}

for attempt in 1 2 3; do
  echo "Running UI test attempt $attempt/3..."
  if run_live_ui_test; then
    echo "Live iOS E2E succeeded."
    exit 0
  fi

  if [[ "$attempt" -lt 3 ]]; then
    echo "UI test attempt $attempt failed; resetting simulator state before retry..."
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    sleep 2
  fi
done

echo "Live iOS E2E failed after 3 attempts." >&2
exit 1
