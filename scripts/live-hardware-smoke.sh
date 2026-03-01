#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

APP_SUPPORT_ROOT="${RUBBER_DUCK_APP_SUPPORT:-$HOME/Library/Application Support/RubberDuck}"
LOG_FILE="${RUBBER_DUCK_LOG_PATH:-$APP_SUPPORT_ROOT/RubberDuck.log}"
ARTIFACT_DIR="${RUBBER_DUCK_SMOKE_DIR:-/tmp/rubber-duck-live-smoke}"
QUESTION_CLIP="$ARTIFACT_DIR/question.aiff"
INTERRUPT_CLIP="$ARTIFACT_DIR/interrupt.aiff"

QUESTION_TEXT="${RUBBER_DUCK_SMOKE_QUESTION_TEXT:-Can you list five debugging steps for a failing Xcode build and explain each briefly?}"
INTERRUPT_TEXT="${RUBBER_DUCK_SMOKE_INTERRUPT_TEXT:-Stop. Summarize in one sentence.}"
VOICE_NAME="${RUBBER_DUCK_SMOKE_VOICE:-Samantha}"
SPEECH_RATE="${RUBBER_DUCK_SMOKE_RATE:-180}"
WAIT_TIMEOUT_SECONDS="${RUBBER_DUCK_SMOKE_WAIT_TIMEOUT_SECONDS:-20}"
SETTLE_SECONDS="${RUBBER_DUCK_SMOKE_SETTLE_SECONDS:-4}"

SPEAKING_PATTERN='VoiceSessionCoordinator: State -> speaking'
BARGE_PATTERN='VoiceSessionCoordinator: Barge-in'
CANCEL_PATTERN='VoiceSessionCoordinator: Sent cancel\+truncate|VoiceSessionCoordinator: Sent response.cancel without truncate'

usage() {
  cat <<'EOF'
Usage:
  scripts/live-hardware-smoke.sh prepare
  scripts/live-hardware-smoke.sh run

Environment overrides:
  RUBBER_DUCK_APP_SUPPORT
  RUBBER_DUCK_LOG_PATH
  RUBBER_DUCK_SMOKE_DIR
  RUBBER_DUCK_SMOKE_QUESTION_TEXT
  RUBBER_DUCK_SMOKE_INTERRUPT_TEXT
  RUBBER_DUCK_SMOKE_VOICE
  RUBBER_DUCK_SMOKE_RATE
  RUBBER_DUCK_SMOKE_WAIT_TIMEOUT_SECONDS
  RUBBER_DUCK_SMOKE_SETTLE_SECONDS
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

ensure_dependencies() {
  require_cmd say
  require_cmd afplay
  require_cmd rg
}

generate_clips() {
  mkdir -p "$ARTIFACT_DIR"

  say -v "$VOICE_NAME" -r "$SPEECH_RATE" -o "$QUESTION_CLIP" -- "$QUESTION_TEXT"
  say -v "$VOICE_NAME" -r "$SPEECH_RATE" -o "$INTERRUPT_CLIP" -- "$INTERRUPT_TEXT"

  echo "Generated:"
  echo "  $QUESTION_CLIP"
  echo "  $INTERRUPT_CLIP"
}

line_count() {
  if [[ -f "$LOG_FILE" ]]; then
    wc -l < "$LOG_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

print_log_delta() {
  local start_line="$1"
  if [[ ! -f "$LOG_FILE" ]]; then
    return
  fi
  sed -n "$((start_line + 1)),\$p" "$LOG_FILE"
}

wait_for_speaking() {
  local start_line="$1"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if print_log_delta "$start_line" | rg -q "$SPEAKING_PATTERN"; then
      return 0
    fi

    local now
    now="$(date +%s)"
    if (( now - start_ts >= WAIT_TIMEOUT_SECONDS )); then
      return 1
    fi
    sleep 0.2
  done
}

run_smoke() {
  if ! pgrep -x RubberDuck >/dev/null 2>&1; then
    echo "RubberDuck app is not running. Start it first."
    exit 1
  fi

  if [[ ! -f "$QUESTION_CLIP" || ! -f "$INTERRUPT_CLIP" ]]; then
    echo "Sample clips missing; generating now."
    generate_clips
  fi

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found at: $LOG_FILE"
    echo "Start a voice session first (Option+D), then retry."
    exit 1
  fi

  echo "Precondition: start RubberDuck voice listening now (Option+D)."
  echo "Running sample scenario:"
  echo "  1) Play question clip"
  echo "  2) Wait for assistant speaking log"
  echo "  3) Play interruption clip"
  echo

  local baseline_line
  baseline_line="$(line_count)"

  afplay "$QUESTION_CLIP"

  if ! wait_for_speaking "$baseline_line"; then
    echo "Timed out waiting for assistant speaking state in logs."
    echo "Recent logs:"
    tail -n 80 "$LOG_FILE" || true
    exit 2
  fi

  afplay "$INTERRUPT_CLIP"
  sleep "$SETTLE_SECONDS"

  local log_delta
  log_delta="$(print_log_delta "$baseline_line")"

  local saw_barge_in=0
  local saw_abort=0
  if echo "$log_delta" | rg -q "$BARGE_PATTERN"; then
    saw_barge_in=1
  fi
  if echo "$log_delta" | rg -q "$CANCEL_PATTERN"; then
    saw_abort=1
  fi

  echo
  echo "Smoke result:"
  echo "  barge_detected=$saw_barge_in"
  echo "  abort_sent=$saw_abort"

  if (( saw_barge_in == 1 && saw_abort == 1 )); then
    echo "PASS: Barge-in path observed in live logs."
    echo
    echo "Matched log lines:"
    echo "$log_delta" | rg "$BARGE_PATTERN|$CANCEL_PATTERN" || true
    exit 0
  fi

  echo "FAIL: Expected barge-in markers were not both present."
  echo
  echo "Recent log excerpt:"
  echo "$log_delta" | tail -n 120 || true
  exit 3
}

main() {
  case "$MODE" in
    prepare)
      ensure_dependencies
      generate_clips
      ;;
    run)
      ensure_dependencies
      run_smoke
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Unknown mode: $MODE" >&2
      usage
      exit 1
      ;;
  esac
}

main
