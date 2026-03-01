import type {
  EventRenderer,
  RendererOptions,
  RendererPiEvent,
  ToolContent,
} from "../types.js";
import { createColorStyles } from "./colors.js";
import { formatTag, formatToolArgs, formatUserMessage } from "./format.js";
import { ToolTracker } from "./tool-tracker.js";

type StreamState = "idle" | "text" | "thinking";

const STATUS_DEBOUNCE_MS = 200;
const USER_LABEL = "User:";
const DUCK_LABEL = "Duck:";
const write = (s: string) => process.stdout.write(s);

function extractToolText(content: ToolContent): string {
  return content.content
    .filter((c) => c.type === "text")
    .map((c) => c.text ?? "")
    .join("\n");
}

export function createTextRenderer(options: RendererOptions): EventRenderer {
  const styles = createColorStyles(options.color);
  const tag = styles.tag;
  const text = styles.text;
  let state: StreamState = "idle";
  const tracker = new ToolTracker();
  const toolStartTimes = new Map<string, number>();
  const streamedTools = new Set<string>();
  let lastStatusMessage: string | null = null;
  let statusDebounceTimer: ReturnType<typeof setTimeout> | null = null;

  function flushPendingStatus(): void {
    if (statusDebounceTimer !== null) {
      clearTimeout(statusDebounceTimer);
      statusDebounceTimer = null;
    }
  }

  function ensureIdle(): void {
    if (state !== "idle") {
      write("\n");
      state = "idle";
    }
  }

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Event rendering is intentionally centralized for deterministic terminal output ordering.
  function renderEvent(event: RendererPiEvent): void {
    if (
      !(event.type === "extension_ui_request" && event.method === "setStatus")
    ) {
      flushPendingStatus();
    }

    switch (event.type) {
      case "agent_start":
        break;

      case "agent_end":
        if (options.verbose) {
          write(`${text.dim("--- end ---")}\n`);
        }
        break;

      case "turn_start":
        if (options.verbose) {
          write(`${text.dim("--- turn ---")}\n`);
        }
        break;

      case "turn_end":
        break;

      case "message_start":
        if (event.message.role === "user") {
          const body = formatUserMessage(event.message);
          if (body) {
            write(`${tag.you(USER_LABEL)} ${text.you(body)}\n\n`);
          }
        }
        break;

      case "message_update":
        renderMessageUpdate(event);
        break;

      case "message_end":
        ensureIdle();
        break;

      case "tool_execution_start":
        ensureIdle();
        toolStartTimes.set(event.toolCallId, Date.now());
        write(
          tag.tool(formatTag("tool")) +
            " " +
            text.toolName(event.toolName) +
            " " +
            text.toolArgs(formatToolArgs(event.args)) +
            "\n"
        );
        break;

      case "tool_execution_update":
        renderToolUpdate(event);
        break;

      case "tool_execution_end":
        renderToolEnd(event);
        break;

      case "auto_compaction_start":
        write(
          tag.compact(formatTag("compact")) +
            " " +
            text.dim(`Compacting context (${event.reason})...`) +
            "\n"
        );
        break;

      case "auto_compaction_end":
        if (event.aborted) {
          write(
            tag.compact(formatTag("compact")) +
              " " +
              text.dim(
                event.willRetry
                  ? "Compaction aborted, will retry"
                  : "Compaction aborted"
              ) +
              "\n"
          );
        } else if (event.errorMessage) {
          write(
            tag.error(formatTag("error")) +
              " " +
              text.error(`Compaction failed: ${event.errorMessage}`) +
              "\n"
          );
        } else if (event.result) {
          write(
            tag.compact(formatTag("compact")) +
              " " +
              text.dim(`Done (${event.result.tokensBefore} tokens before)`) +
              "\n"
          );
        }
        break;

      case "auto_retry_start":
        write(
          tag.retry(formatTag("retry")) +
            " " +
            text.dim(
              `Attempt ${event.attempt}/${event.maxAttempts} in ${event.delayMs}ms: ${event.errorMessage}`
            ) +
            "\n"
        );
        break;

      case "auto_retry_end":
        if (event.success) {
          write(
            tag.retry(formatTag("retry")) +
              " " +
              text.dim(`Succeeded on attempt ${event.attempt}`) +
              "\n"
          );
        } else {
          write(
            tag.error(formatTag("error")) +
              " " +
              text.error(
                `All retry attempts failed${event.finalError ? `: ${event.finalError}` : ""}`
              ) +
              "\n"
          );
        }
        break;

      case "extension_error":
        write(
          tag.error(formatTag("error")) +
            " " +
            text.error(
              `Extension ${event.extensionPath} (${event.event}): ${event.error}`
            ) +
            "\n"
        );
        break;

      case "prompt_error":
        write(
          tag.error(formatTag("error")) +
            " " +
            text.error(`Prompt failed: ${event.error}`) +
            "\n"
        );
        break;

      case "extension_ui_request":
        renderUiRequest(event);
        break;

      case "app_history_event":
        renderAppHistoryEvent(event);
        break;

      default:
        break;
    }
  }

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Streaming deltas require explicit state-machine handling for readability.
  function renderMessageUpdate(
    event: Extract<RendererPiEvent, { type: "message_update" }>
  ): void {
    const delta = event.assistantMessageEvent;

    switch (delta.type) {
      case "text_start":
        ensureIdle();
        write(`${tag.assistant(DUCK_LABEL)} `);
        state = "text";
        break;

      case "text_delta":
        if (!delta.delta) {
          break;
        }
        if (state !== "text") {
          ensureIdle();
          write(`${tag.assistant(DUCK_LABEL)} `);
          state = "text";
        }
        write(text.assistant(delta.delta));
        break;

      case "text_end":
        if (state === "text") {
          write("\n\n");
          state = "idle";
        }
        break;

      case "thinking_start":
        if (options.showThinking) {
          ensureIdle();
          write(`${tag.thinking(formatTag("thinking"))} `);
          state = "thinking";
        }
        break;

      case "thinking_delta":
        if (options.showThinking && state === "thinking" && delta.delta) {
          write(text.thinking(delta.delta));
        }
        break;

      case "thinking_end":
        if (state === "thinking") {
          write("\n");
          state = "idle";
        }
        break;

      case "error":
        ensureIdle();
        write(
          tag.error(formatTag("error")) +
            " " +
            text.error(delta.reason ?? "Unknown error") +
            "\n"
        );
        break;

      // toolcall_start, toolcall_delta, toolcall_end, start, done — silent
      default:
        break;
    }
  }

  function renderToolUpdate(
    event: Extract<RendererPiEvent, { type: "tool_execution_update" }>
  ): void {
    const accumulated = extractToolText(event.partialResult);
    const newContent = tracker.getNewOutput(event.toolCallId, accumulated);
    if (!newContent) {
      return;
    }

    streamedTools.add(event.toolCallId);

    const lines = newContent.split("\n");
    for (const line of lines) {
      if (line) {
        write(`  ${text.dim(line)}\n`);
      }
    }
  }

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Tool end handling needs explicit branches for streamed/non-streamed and error/success output.
  function renderToolEnd(
    event: Extract<RendererPiEvent, { type: "tool_execution_end" }>
  ): void {
    tracker.complete(event.toolCallId);
    const hadStreaming = streamedTools.delete(event.toolCallId);

    const startTime = toolStartTimes.get(event.toolCallId);
    toolStartTimes.delete(event.toolCallId);
    const durationMs = startTime !== undefined ? Date.now() - startTime : null;
    const durationStr = durationMs !== null ? `[${durationMs}ms]` : null;

    if (event.isError) {
      write(
        tag.error(formatTag("error")) +
          " " +
          text.error(`${event.toolName} failed`) +
          (durationStr ? ` ${text.dim(durationStr)}` : "") +
          "\n"
      );
      const errorText = extractToolText(event.result);
      if (errorText) {
        for (const line of errorText.split("\n")) {
          if (line) {
            write(`  ${text.error(line)}\n`);
          }
        }
      }
    } else if (!hadStreaming) {
      const resultText = extractToolText(event.result);
      if (resultText) {
        for (const line of resultText.split("\n")) {
          if (line) {
            write(`  ${text.dim(line)}\n`);
          }
        }
      }
    }

    if (durationStr && !event.isError) {
      write(`  ${text.dim(durationStr)}\n`);
    }
    write("\n");
  }

  function renderUiRequest(
    event: Extract<RendererPiEvent, { type: "extension_ui_request" }>
  ): void {
    switch (event.method) {
      case "setStatus":
        // Internal agent status (e.g. "Thinking...") — show only in verbose mode.
        // In default mode these are noise; streaming text is sufficient feedback.
        if (options.verbose && event.message) {
          if (event.message === lastStatusMessage) {
            break;
          }
          flushPendingStatus();
          const statusMessage = event.message;
          statusDebounceTimer = setTimeout(() => {
            statusDebounceTimer = null;
            lastStatusMessage = statusMessage;
            write(`${tag.ui(formatTag("ui"))} ${text.output(statusMessage)}\n`);
          }, STATUS_DEBOUNCE_MS);
        }
        break;

      case "notify":
      case "setWidget":
      case "setTitle":
      case "set_editor_text":
        if (event.message) {
          write(`${tag.ui(formatTag("ui"))} ${text.output(event.message)}\n`);
        }
        break;

      case "confirm":
      case "select":
      case "input":
      case "editor":
        write(
          tag.ui(formatTag("ui")) +
            " " +
            text.output(event.message ?? event.method) +
            "\n"
        );
        break;

      default:
        break;
    }
  }

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: App history maps multiple event types to distinct terminal output shapes.
  function renderAppHistoryEvent(
    event: Extract<RendererPiEvent, { type: "app_history_event" }>
  ): void {
    ensureIdle();

    switch (event.appEventType) {
      case "assistant_audio":
        if (event.text) {
          write(`${tag.assistant(DUCK_LABEL)} ${text.assistant(event.text)}\n`);
        }
        break;

      case "assistant_text":
        if (event.text) {
          write(`${tag.assistant(DUCK_LABEL)} ${text.assistant(event.text)}\n`);
        }
        break;

      case "user_text":
        if (event.text) {
          write(`${tag.you(USER_LABEL)} ${text.you(event.text)}\n`);
        }
        break;

      case "user_audio": {
        if (event.text) {
          write(`${tag.you(USER_LABEL)} ${text.you(event.text)}\n`);
          break;
        }
        const state = event.metadata?.state ?? "activity";
        if (!options.verbose) {
          if (state === "speech_stopped") {
            write(`${tag.you(USER_LABEL)} ${text.you("[voice message]")}\n`);
          }
          break;
        }
        write(`${tag.you(formatTag("voice"))} ${text.you(state)}\n`);
        break;
      }

      case "tool_call": {
        const tool = event.metadata?.tool;
        const state = event.metadata?.state;
        const callId = event.metadata?.call_id;
        const args = event.metadata?.arguments;

        const details: string[] = [];
        if (state) {
          details.push(state);
        }
        if (tool) {
          details.push(`tool=${tool}`);
        }
        if (callId) {
          details.push(`call=${callId}`);
        }
        if (args) {
          details.push(`args=${args}`);
        }

        const message =
          details.length > 0 ? details.join(" ") : "tool activity";
        write(`${tag.tool(formatTag("tool:voice"))} ${text.output(message)}\n`);
        break;
      }

      default:
        if (options.verbose) {
          const label = event.appEventType || "event";
          const body = event.text || "";
          write(
            `${tag.ui(formatTag("app"))} ${text.output(`${label} ${body}`.trim())}\n`
          );
        }
        break;
    }
  }

  return {
    render(event: RendererPiEvent): void {
      renderEvent(event);
    },
    cleanup(): void {
      flushPendingStatus();
      ensureIdle();
      tracker.reset();
      toolStartTimes.clear();
      streamedTools.clear();
      lastStatusMessage = null;
    },
  };
}
