import { type Command, Option } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { createColorize, defaultColorEnabled } from "../renderer/colors.js";
import { createRenderer } from "../renderer/index.js";
import type { DaemonEvent, PiEvent } from "../types.js";
import { ensureFollowing } from "./session-bootstrap.js";
import { createStreamLifecycle } from "./stream-lifecycle.js";
import { handleUiEvent } from "./ui-response.js";

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
    .action(async (messageParts: string[], options) => {
      const message = messageParts.join(" ");
      const color =
        typeof options.color === "boolean"
          ? options.color
          : defaultColorEnabled();
      const colorize = createColorize(color);

      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        // Follow the session (auto-attaching if needed)
        const followResp = await ensureFollowing(
          client,
          options.session as string | undefined
        );
        if (!followResp.ok) {
          console.error(colorize("red", `Error: ${followResp.error}`));
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

        // Track when agent finishes
        let agentDone = false;
        let agentStarted = false;
        let commandOnlyTimer: ReturnType<typeof setTimeout> | null = null;

        client.onEvent((event: DaemonEvent) => {
          const piEvent = event.data as PiEvent;
          renderer.render(piEvent);
          handleUiEvent(event, client, { interactive });

          if (piEvent.type === "agent_start") {
            agentStarted = true;
            if (commandOnlyTimer) {
              clearTimeout(commandOnlyTimer);
              commandOnlyTimer = null;
            }
          }

          if (piEvent.type === "agent_end") {
            agentDone = true;
            if (commandOnlyTimer) {
              clearTimeout(commandOnlyTimer);
              commandOnlyTimer = null;
            }
            renderer.cleanup();
            client.close();
            process.exit(0);
          }
        });

        // Send the message
        const sayResp = await client.request("say", {
          message,
          sessionId: options.session as string | undefined,
        });
        if (!sayResp.ok) {
          console.error(colorize("red", `Error: ${sayResp.error}`));
          renderer.cleanup();
          client.close();
          process.exit(1);
        }

        // Extension commands can complete without triggering an agent turn.
        commandOnlyTimer = setTimeout(() => {
          if (!(agentDone || agentStarted)) {
            renderer.cleanup();
            client.close();
            process.exit(0);
          }
        }, 10_000);

        const clearTimers = () => {
          if (commandOnlyTimer) {
            clearTimeout(commandOnlyTimer);
            commandOnlyTimer = null;
          }
        };

        const lifecycle = createStreamLifecycle(client, renderer, colorize, {
          abortOnInterrupt: true,
          onCleanup: clearTimers,
        });

        // Timeout: if agent doesn't finish in 10 minutes, exit
        setTimeout(() => {
          if (!agentDone) {
            console.error(colorize("yellow", "\nOperation timed out."));
            lifecycle.cleanup();
          }
        }, 600_000);
      } catch (err) {
        console.error(
          colorize(
            "red",
            `Error: ${err instanceof Error ? err.message : String(err)}`
          )
        );
        process.exit(1);
      }
    });
}
