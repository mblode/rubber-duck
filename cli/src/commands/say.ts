import { log, spinner } from "@clack/prompts";
import { type Command, Option } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { defaultColorEnabled } from "../renderer/colors.js";
import { createRenderer } from "../renderer/index.js";
import type { DaemonEvent, PiEvent } from "../types.js";
import { ensureFollowing } from "./session-bootstrap.js";
import { createStreamLifecycle } from "./stream-lifecycle.js";
import { handleUiEvent } from "./ui-response.js";

export function isVisibleProgressEvent(
  event: PiEvent,
  showThinking: boolean
): boolean {
  switch (event.type) {
    case "message_update": {
      const deltaType = event.assistantMessageEvent.type;
      if (
        deltaType === "text_start" ||
        deltaType === "text_delta" ||
        deltaType === "text_end" ||
        deltaType === "error"
      ) {
        return true;
      }
      if (
        showThinking &&
        (deltaType === "thinking_start" ||
          deltaType === "thinking_delta" ||
          deltaType === "thinking_end")
      ) {
        return true;
      }
      return false;
    }
    case "tool_execution_start":
    case "tool_execution_update":
    case "tool_execution_end":
    case "auto_compaction_start":
    case "auto_compaction_end":
    case "auto_retry_start":
    case "auto_retry_end":
    case "extension_error":
    case "prompt_error":
      return true;
    case "extension_ui_request":
      return event.method !== "setStatus";
    default:
      return false;
  }
}

export function registerSayCommand(program: Command): void {
  program
    .command("say <message...>")
    .description("Send a message to the active session")
    .option("--json", "Output raw NDJSON events")
    .addOption(
      new Option("--session <id>", "Target a specific session").hideHelp()
    )
    .addOption(
      new Option("--show-thinking", "Display model thinking blocks").hideHelp()
    )
    .addOption(new Option("--color", "Force color output").hideHelp())
    .addOption(new Option("--no-color", "Disable color output").hideHelp())
    // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Sequential agent lifecycle branches (spinner, timers, events) are clearer inline.
    .action(async (messageParts: string[], options) => {
      const message = messageParts.join(" ");
      const color =
        typeof options.color === "boolean"
          ? options.color
          : defaultColorEnabled();

      try {
        await ensureDaemon({ quiet: options.json ?? false });
        const client = await DaemonClient.connect();

        // Follow the session (auto-attaching if needed)
        const followResp = await ensureFollowing(
          client,
          options.session as string | undefined
        );
        if (!followResp.ok) {
          log.error(followResp.error ?? "Failed to follow session");
          client.close();
          process.exit(1);
        }

        const interactive =
          !options.json &&
          (process.stdin.isTTY ?? false) &&
          (process.stdout.isTTY ?? false);

        const renderer = createRenderer({
          json: options.json ?? false,
          showThinking: options.showThinking ?? false,
          verbose: false,
          color,
        });
        const showThinking = options.showThinking ?? false;

        // Track when agent finishes
        let agentDone = false;
        let agentStarted = false;
        let commandOnlyTimer: ReturnType<typeof setTimeout> | null = null;
        let waitSpinner: ReturnType<typeof spinner> | null = null;
        let sawVisibleProgress = false;

        const stopWaitSpinner = () => {
          if (waitSpinner) {
            waitSpinner.stop();
            waitSpinner = null;
          }
        };

        const clearTimers = () => {
          stopWaitSpinner();
          if (commandOnlyTimer) {
            clearTimeout(commandOnlyTimer);
            commandOnlyTimer = null;
          }
        };

        // Keep lightweight feedback active until we render real stream output.
        if (!options.json && (process.stdout.isTTY ?? false)) {
          waitSpinner = spinner();
          waitSpinner.start("Thinking...");
        }

        client.onEvent((event: DaemonEvent) => {
          const piEvent = event.data as PiEvent;

          if (piEvent.type === "agent_start") {
            agentStarted = true;
            if (commandOnlyTimer) {
              clearTimeout(commandOnlyTimer);
              commandOnlyTimer = null;
            }
          }

          if (
            !sawVisibleProgress &&
            isVisibleProgressEvent(piEvent, showThinking)
          ) {
            sawVisibleProgress = true;
            stopWaitSpinner();
          }

          renderer.render(piEvent);
          handleUiEvent(event, client, { interactive });

          if (piEvent.type === "agent_end") {
            agentDone = true;
            clearTimers();
            renderer.cleanup();
            client.close();
            process.exit(0);
          }

          if (piEvent.type === "prompt_error") {
            clearTimers();
            renderer.cleanup();
            client.close();
            log.error(piEvent.error);
            process.exit(1);
          }
        });

        // Send the message
        const sayResp = await client.request("say", {
          message,
          sessionId: options.session as string | undefined,
        });
        if (!sayResp.ok) {
          clearTimers();
          log.error(sayResp.error ?? "Failed to send message");
          renderer.cleanup();
          client.close();
          process.exit(1);
        }

        // Extension commands can complete without triggering an agent turn.
        commandOnlyTimer = setTimeout(() => {
          if (!(agentDone || agentStarted)) {
            clearTimers();
            renderer.cleanup();
            client.close();
            process.exit(0);
          }
        }, 10_000);

        const lifecycle = createStreamLifecycle(client, renderer, {
          abortOnInterrupt: true,
          onCleanup: clearTimers,
        });

        // Timeout: if agent doesn't finish in 10 minutes, exit
        setTimeout(() => {
          if (!agentDone) {
            log.warn("Operation timed out.");
            lifecycle.cleanup();
          }
        }, 600_000);
      } catch (err) {
        log.error(`${err instanceof Error ? err.message : String(err)}`);
        process.exit(1);
      }
    });
}
