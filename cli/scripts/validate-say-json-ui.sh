#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${CLI_DIR}/.." && pwd)"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/duck-say-json-ui.XXXXXX")"
TEST_HOME="${WORK_DIR}/home"
WRAPPER_BIN_DIR="${WORK_DIR}/bin"
WRAPPER_LOG="${WORK_DIR}/pi-wrapper.ndjson"
SAY_STDOUT="${WORK_DIR}/say-output.ndjson"
SAY_STDERR="${WORK_DIR}/say-stderr.log"
KEEP_WORK_DIR="${KEEP_DUCK_UI_VALIDATION_DIR:-0}"

cleanup() {
  local pid_file
  local daemon_pid

  pid_file="${TEST_HOME}/Library/Application Support/RubberDuck/duck-daemon.pid"
  if [[ -f "${pid_file}" ]]; then
    daemon_pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ "${daemon_pid}" =~ ^[0-9]+$ ]]; then
      kill "${daemon_pid}" >/dev/null 2>&1 || true
      sleep 0.1
      kill -9 "${daemon_pid}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${KEEP_WORK_DIR}" == "1" ]]; then
    echo "Kept validation artifacts in ${WORK_DIR}"
    return
  fi

  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT INT TERM

mkdir -p "${TEST_HOME}" "${WRAPPER_BIN_DIR}"

cat >"${WRAPPER_BIN_DIR}/pi" <<'WRAPPER'
#!/usr/bin/env node
const { appendFileSync } = require("node:fs");
const readline = require("node:readline");

const logPath = process.env.DUCK_PI_WRAPPER_LOG;
const uiRequestId = "duck-ui-request-1";
let promptSeen = false;
let agentEnded = false;
let endTimer = null;

function log(entry) {
  if (!logPath) {
    return;
  }
  appendFileSync(logPath, `${JSON.stringify(entry)}\n`);
}

function send(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
  log({ direction: "out", ...payload });
}

function sendResponse(id, command, success, data, error) {
  const response = { type: "response", success, command };
  if (typeof id === "string") {
    response.id = id;
  }
  if (typeof data !== "undefined") {
    response.data = data;
  }
  if (typeof error === "string") {
    response.error = error;
  }
  send(response);
}

function endAgent(reason) {
  if (agentEnded) {
    return;
  }
  agentEnded = true;
  if (endTimer) {
    clearTimeout(endTimer);
    endTimer = null;
  }
  send({
    type: "agent_end",
    messages: [{ role: "assistant", content: `wrapper-finished:${reason}` }],
  });
}

function handlePrompt(request) {
  promptSeen = true;
  send({ type: "agent_start" });
  send({
    type: "extension_ui_request",
    id: uiRequestId,
    method: "input",
    title: "Wrapper validation prompt",
    message: "Enter a value",
    placeholder: "value",
  });
  sendResponse(request.id, "prompt", true, { accepted: true });

  // Keep runtime bounded even if no UI response is forwarded.
  endTimer = setTimeout(() => endAgent("timeout"), 3000);
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) {
    return;
  }

  let request;
  try {
    request = JSON.parse(line);
  } catch {
    log({ direction: "in", parseError: line });
    return;
  }

  log({ direction: "in", ...request });

  switch (request.type) {
    case "get_state":
      sendResponse(request.id, "get_state", true, {
        autoCompactionEnabled: false,
        isCompacting: false,
        isStreaming: false,
        messageCount: 0,
        model: "pi-wrapper-model",
        pendingMessageCount: 0,
        sessionFile: "/tmp/pi-wrapper-session.jsonl",
        sessionId: "pi-wrapper-session",
        sessionName: "pi-wrapper",
        thinkingLevel: "off",
      });
      break;

    case "prompt":
      handlePrompt(request);
      break;

    case "extension_ui_response":
      if (promptSeen) {
        endAgent("ui-response");
      }
      break;

    case "abort":
    case "abort_bash":
      sendResponse(request.id, request.type, true, {});
      endAgent(request.type);
      break;

    default:
      if (typeof request.id === "string") {
        sendResponse(
          request.id,
          String(request.type ?? "unknown"),
          false,
          undefined,
          `Unsupported command: ${String(request.type ?? "unknown")}`
        );
      }
      break;
  }
});

rl.on("close", () => {
  if (promptSeen && !agentEnded) {
    endAgent("stdin-closed");
  }
  process.exit(0);
});
WRAPPER

chmod +x "${WRAPPER_BIN_DIR}/pi"
touch "${WRAPPER_LOG}"

export HOME="${TEST_HOME}"
export PATH="${WRAPPER_BIN_DIR}:${PATH}"
export DUCK_PI_WRAPPER_LOG="${WRAPPER_LOG}"
export RUBBER_DUCK_PI_BINARY="${WRAPPER_BIN_DIR}/pi"

cd "${CLI_DIR}"
npm run build >/dev/null

DUCK_CMD=(node "${CLI_DIR}/dist/cli.js")

if ! (
  cd "${REPO_DIR}" &&
    "${DUCK_CMD[@]}" say --json "validate extension ui flow"
) >"${SAY_STDOUT}" 2>"${SAY_STDERR}"; then
  echo "duck say --json failed" >&2
  cat "${SAY_STDERR}" >&2 || true
  exit 1
fi

node - "${SAY_STDOUT}" "${WRAPPER_LOG}" <<'CHECK'
const { readFileSync } = require("node:fs");

const [sayOutputPath, wrapperLogPath] = process.argv.slice(2);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function parseNdjson(path, label) {
  const raw = readFileSync(path, "utf8");
  const lines = raw.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const parsed = [];

  for (const line of lines) {
    try {
      parsed.push(JSON.parse(line));
    } catch {
      fail(`${label} contains invalid JSON line: ${line}`);
    }
  }

  return parsed;
}

const events = parseNdjson(sayOutputPath, "duck say output");
const wrapperLog = parseNdjson(wrapperLogPath, "pi wrapper log");

const uiRequest = events.find((event) => event.type === "extension_ui_request");
if (!uiRequest) {
  fail("duck say --json did not emit an extension_ui_request event");
}

const agentStartIndex = events.findIndex((event) => event.type === "agent_start");
if (agentStartIndex === -1) {
  fail("duck say --json did not emit agent_start");
}

const agentEndIndex = events.findIndex((event) => event.type === "agent_end");
if (agentEndIndex === -1) {
  fail("duck say --json did not emit agent_end");
}

if (agentEndIndex < agentStartIndex) {
  fail("agent_end was emitted before agent_start");
}

const promptRequest = wrapperLog.find(
  (entry) => entry.direction === "in" && entry.type === "prompt"
);
if (!promptRequest) {
  fail("Pi wrapper never received prompt command");
}

const uiResponse = wrapperLog.find(
  (entry) => entry.direction === "in" && entry.type === "extension_ui_response"
);
if (!uiResponse) {
  fail("Pi wrapper did not receive extension_ui_response");
}

if (uiResponse.id !== uiRequest.id) {
  fail(
    `extension_ui_response id mismatch: expected ${uiRequest.id}, got ${uiResponse.id}`
  );
}

if (uiResponse.cancelled !== true) {
  fail("Expected extension_ui_response.cancelled to be true in --json mode");
}

console.log(
  "Validation passed: duck say --json emitted extension_ui_request and forwarded cancelled extension_ui_response."
);
CHECK
