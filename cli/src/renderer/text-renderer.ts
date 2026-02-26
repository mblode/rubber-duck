import { createColorStyles } from "./colors.js";
import { formatTag, formatToolArgs, formatUserMessage } from "./format.js";
import { ToolTracker } from "./tool-tracker.js";
import type {
  EventRenderer,
  RendererOptions,
  RendererPiEvent,
  ToolContent,
} from "./types.js";

type StreamState = "idle" | "text" | "thinking";

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
  const streamedTools = new Set<string>();

  function ensureIdle(): void {
    if (state !== "idle") {
      write("\n");
      state = "idle";
    }
  }

  function renderEvent(event: RendererPiEvent): void {
    switch (event.type) {
      case "agent_start":
        break;

      case "agent_end":
        if (options.verbose) {
          write(`${text.dim("--- end ---")}\n`);
        }
        break;

      case "turn_start":
        write(`${text.dim("--- turn ---")}\n`);
        break;

      case "turn_end":
        break;

      case "message_start":
        if (event.message.role === "user") {
          const body = formatUserMessage(event.message);
          if (body) {
            write(`${tag.you(formatTag("you"))} ${text.you(body)}\n\n`);
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

      case "extension_ui_request":
        renderUiRequest(event);
        break;

      default:
        break;
    }
  }

  function renderMessageUpdate(
    event: Extract<RendererPiEvent, { type: "message_update" }>
  ): void {
    const delta = event.assistantMessageEvent;

    switch (delta.type) {
      case "text_start":
        ensureIdle();
        write(`${tag.assistant(formatTag("assistant"))} `);
        state = "text";
        break;

      case "text_delta":
        if (state === "text" && delta.delta) {
          write(text.assistant(delta.delta));
        }
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
        write(`${tag.output(formatTag("output"))} ${text.output(line)}\n`);
      }
    }
  }

  function renderToolEnd(
    event: Extract<RendererPiEvent, { type: "tool_execution_end" }>
  ): void {
    tracker.complete(event.toolCallId);
    const hadStreaming = streamedTools.delete(event.toolCallId);

    if (event.isError) {
      write(
        tag.error(formatTag("error")) +
          " " +
          text.error(`${event.toolName} failed`) +
          "\n"
      );
      const errorText = extractToolText(event.result);
      if (errorText) {
        for (const line of errorText.split("\n")) {
          if (line) {
            write(`${tag.output(formatTag("output"))} ${text.error(line)}\n`);
          }
        }
      }
    } else if (!hadStreaming) {
      const resultText = extractToolText(event.result);
      if (resultText) {
        for (const line of resultText.split("\n")) {
          if (line) {
            write(`${tag.output(formatTag("output"))} ${text.output(line)}\n`);
          }
        }
      }
    }

    write("\n");
  }

  function renderUiRequest(
    event: Extract<RendererPiEvent, { type: "extension_ui_request" }>
  ): void {
    switch (event.method) {
      case "notify":
      case "setStatus":
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

  return {
    render(event: RendererPiEvent): void {
      renderEvent(event);
    },
    cleanup(): void {
      ensureIdle();
      tracker.reset();
      streamedTools.clear();
    },
  };
}
