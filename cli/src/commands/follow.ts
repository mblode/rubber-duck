import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import { log } from "@clack/prompts";
import type { DaemonClient } from "../client.js";
import {
  PI_DEFAULT_THINKING,
  PI_THINKING_OVERRIDE_ENV,
  resolveDefaultPiModel,
} from "../constants.js";
import { createColorize } from "../renderer/colors.js";
import { createRenderer } from "../renderer/index.js";
import type {
  AppHistoryEvent,
  DaemonEvent,
  PiEvent,
  RendererPiEvent,
} from "../types.js";
import { createStreamLifecycle } from "./stream-lifecycle.js";
import { handleUiEvent } from "./ui-response.js";

const APP_HISTORY_POLL_MS = 350;
const NEWLINE_SPLIT_RE = /\r?\n/;

interface AppHistoryFileEvent {
  metadata?: Record<string, string> | null;
  sessionID?: string;
  text?: string | null;
  timestamp?: string;
  type?: string;
}

interface AppHistoryStreamOptions {
  sessionId?: string;
  startFromEnd?: boolean;
}

interface FollowRuntimeOptions {
  color: boolean;
  json: boolean;
  showThinking: boolean;
  verbose: boolean;
}

function toAppHistoryEvent(raw: AppHistoryFileEvent): AppHistoryEvent | null {
  if (!raw.type || typeof raw.type !== "string") {
    return null;
  }

  return {
    type: "app_history_event",
    appEventType: raw.type,
    metadata: raw.metadata ?? undefined,
    sessionID: raw.sessionID,
    text: raw.text ?? undefined,
    timestamp: raw.timestamp,
  };
}

export function startAppHistoryStream(
  filePath: string,
  onEvent: (event: AppHistoryEvent) => void,
  onError: (message: string) => void,
  options: AppHistoryStreamOptions = {}
): () => void {
  let running = true;
  let offsetBytes = 0;
  let carry = "";
  let warnedMissingFile = false;
  let initializedOffset = false;

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Tail a growing JSONL file with offset tracking, carry-over, and robust parse/error handling.
  const pump = () => {
    if (!running) {
      return;
    }
    if (!existsSync(filePath)) {
      if (!warnedMissingFile) {
        warnedMissingFile = true;
        onError(`app history file not created yet: ${filePath}`);
      }
      return;
    }
    warnedMissingFile = false;

    try {
      const raw = readFileSync(filePath);

      if (!initializedOffset) {
        initializedOffset = true;
        if (options.startFromEnd ?? true) {
          offsetBytes = raw.byteLength;
          return;
        }
      }

      if (raw.byteLength < offsetBytes) {
        offsetBytes = 0;
        carry = "";
      }

      const nextChunk = raw.subarray(offsetBytes).toString("utf-8");
      offsetBytes = raw.byteLength;
      if (nextChunk.length === 0 && carry.length === 0) {
        return;
      }

      const lines = `${carry}${nextChunk}`.split(NEWLINE_SPLIT_RE);
      carry = lines.pop() ?? "";

      for (const line of lines) {
        if (!line.trim()) {
          continue;
        }

        let parsed: AppHistoryFileEvent;
        try {
          parsed = JSON.parse(line) as AppHistoryFileEvent;
        } catch {
          onError("Skipping malformed app history JSON line");
          continue;
        }

        const event = toAppHistoryEvent(parsed);
        if (!event) {
          continue;
        }
        if (
          options.sessionId &&
          event.sessionID &&
          event.sessionID !== options.sessionId
        ) {
          continue;
        }
        onEvent(event);
      }
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unknown app history error";
      onError(`Failed to read app history: ${message}`);
    }
  };

  pump();
  const timer = setInterval(pump, APP_HISTORY_POLL_MS);

  return () => {
    running = false;
    clearInterval(timer);
  };
}

function printSessionHeader(
  colorize: ReturnType<typeof createColorize>,
  params: {
    sessionName: string;
    workspacePath: string;
    isRunning: boolean;
    appHistoryFile: string | undefined;
    appHistoryExists: boolean;
    appHistorySizeBytes: number;
    verbose: boolean;
  }
): void {
  const {
    sessionName,
    workspacePath,
    isRunning,
    appHistoryFile,
    appHistoryExists,
    appHistorySizeBytes,
    verbose,
  } = params;
  const shortPath = workspacePath.startsWith(homedir())
    ? `~${workspacePath.slice(homedir().length)}`
    : workspacePath;
  const model = resolveDefaultPiModel() ?? "default";
  const thinking =
    process.env[PI_THINKING_OVERRIDE_ENV]?.trim() ?? PI_DEFAULT_THINKING;
  const modelInfo = colorize("dim", `[${model} · thinking:${thinking}]`);
  log.step(
    `${colorize("bold", sessionName)}  ${colorize("dim", shortPath)}  ${modelInfo}`
  );
  if (!isRunning) {
    log.warn("Session is idle — run `duck say …` to start");
  }
  if (verbose && appHistoryFile) {
    const historyStatus = appHistoryExists
      ? `ready (${appHistorySizeBytes} bytes)`
      : "not created yet";
    log.info(
      `app_history=${JSON.stringify(appHistoryFile)} (${historyStatus})`
    );
  }
  process.stdout.write("\n");
}

export async function startFollowStream(
  client: DaemonClient,
  sessionArg: string | undefined,
  options: FollowRuntimeOptions
): Promise<void> {
  const colorize = createColorize(options.color);

  const response = await client.request("follow", {
    sessionId: sessionArg,
  });

  if (!response.ok) {
    throw new Error(response.error ?? "Failed to start follow stream");
  }

  const {
    sessionName,
    workspacePath,
    sessionId,
    isRunning,
    appHistoryFile,
    appHistoryExists = false,
    appHistorySizeBytes = 0,
  } = response.data as {
    appHistoryExists?: boolean;
    appHistorySizeBytes?: number;
    appHistoryFile?: string;
    isRunning: boolean;
    sessionId: string;
    sessionName: string;
    workspacePath: string;
  };

  const interactive =
    !options.json &&
    (process.stdin.isTTY ?? false) &&
    (process.stdout.isTTY ?? false);

  const renderer = createRenderer({
    color: options.color,
    json: options.json,
    showThinking: options.showThinking,
    verbose: options.verbose,
  });

  // Print session header (unless JSON mode)
  if (!options.json) {
    printSessionHeader(colorize, {
      sessionName,
      workspacePath,
      isRunning,
      appHistoryFile,
      appHistoryExists,
      appHistorySizeBytes,
      verbose: options.verbose,
    });
  }

  let hasReceivedEvents = false;
  let idleHintTimer: ReturnType<typeof setTimeout> | null = null;
  if (!options.json) {
    idleHintTimer = setTimeout(() => {
      if (!hasReceivedEvents) {
        log.info("Waiting for session activity...");
      }
    }, 4000);
  }

  // Listen for daemon events.
  client.onEvent((event: DaemonEvent) => {
    hasReceivedEvents = true;
    if (idleHintTimer) {
      clearTimeout(idleHintTimer);
      idleHintTimer = null;
    }

    const piEvent = event.data as PiEvent;
    renderer.render(piEvent as RendererPiEvent);
    handleUiEvent(event, client, { interactive });
  });

  // Listen for app voice history updates.
  let appHistoryWarningShown = false;
  const stopAppHistory =
    appHistoryFile && appHistoryFile.length > 0
      ? startAppHistoryStream(
          appHistoryFile,
          (event) => {
            hasReceivedEvents = true;
            if (idleHintTimer) {
              clearTimeout(idleHintTimer);
              idleHintTimer = null;
            }
            renderer.render(event);
          },
          (message) => {
            if (!options.verbose && message.includes("not created yet")) {
              return;
            }
            if (!options.json && (options.verbose || !appHistoryWarningShown)) {
              log.warn(message);
              appHistoryWarningShown = true;
            }
          },
          {
            sessionId,
            startFromEnd: appHistoryExists,
          }
        )
      : () => undefined;

  // Inline text input: when running interactively, each typed line is sent as a prompt.
  let rl: ReturnType<typeof createInterface> | null = null;
  if (interactive) {
    rl = createInterface({ input: process.stdin, terminal: false });
    rl.on("line", (line) => {
      const message = line.trim();
      if (!message) {
        return;
      }
      client.request("say", { message, sessionId }).catch((err) => {
        log.error(err instanceof Error ? err.message : String(err));
      });
    });
  }

  createStreamLifecycle(client, renderer, {
    unfollowOnCleanup: true,
    onCleanup: () => {
      rl?.close();
      if (idleHintTimer) {
        clearTimeout(idleHintTimer);
        idleHintTimer = null;
      }
      stopAppHistory();
    },
  });
}
