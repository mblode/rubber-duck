import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { defaultColorEnabled } from "../renderer/colors.js";
import { createRenderer } from "../renderer/index.js";
import type { DaemonEvent, PiEvent } from "../types.js";
import { handleUiEvent } from "./ui-response.js";

export function registerFollowCommand(program: Command): void {
  program
    .command("follow [session]")
    .description("Stream live events from a session")
    .option("--json", "Output raw NDJSON events")
    .option("--show-thinking", "Display model thinking blocks")
    .option("--verbose", "Show all lifecycle events")
    .option("--color", "Force color output")
    .option("--no-color", "Disable color output")
    .action(async (sessionArg: string | undefined, options) => {
      const color =
        typeof options.color === "boolean"
          ? options.color
          : defaultColorEnabled();
      const colorize = (
        format: Parameters<typeof styleText>[0],
        value: string
      ) => (color ? styleText(format, value) : value);

      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const params: Record<string, unknown> = {};
        if (sessionArg) {
          params.sessionId = sessionArg;
        }

        const response = await client.request("follow", params);

        if (!response.ok) {
          console.error(colorize("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { sessionName, workspacePath, sessionId } = response.data as {
          sessionId: string;
          sessionName: string;
          workspacePath: string;
          isRunning: boolean;
        };

        const interactive =
          !options.json &&
          (process.stdin.isTTY ?? false) &&
          (process.stdout.isTTY ?? false);

        const renderer = createRenderer({
          json: options.json ?? false,
          showThinking: options.showThinking ?? false,
          verbose: options.verbose ?? false,
          color,
        });

        // Print session header (unless JSON mode)
        if (!options.json) {
          const tag = colorize(["bold", "blue"], "[session]");
          console.log(
            `${tag} ${colorize("blue", `workspace=${workspacePath}`)}`
          );
          console.log(
            `${tag} ${colorize("blue", `session=${sessionName} (id: ${sessionId.slice(0, 8)})`)}`
          );
          console.log();
        }

        // Listen for events
        client.onEvent((event: DaemonEvent) => {
          const piEvent = event.data as PiEvent;
          renderer.render(piEvent);
          handleUiEvent(event, client, { interactive });
        });

        let checkConnection: ReturnType<typeof setInterval> | null = null;
        let isCleaningUp = false;

        // Handle graceful shutdown
        const cleanup = () => {
          if (isCleaningUp) {
            return;
          }
          isCleaningUp = true;

          if (checkConnection) {
            clearInterval(checkConnection);
            checkConnection = null;
          }

          renderer.cleanup();
          client.request("unfollow", {}).catch(() => {
            // Best-effort cleanup on shutdown
          });
          setTimeout(() => {
            client.close();
            process.exit(0);
          }, 100);
        };

        process.once("SIGINT", cleanup);
        process.once("SIGTERM", cleanup);

        // Handle daemon disconnect
        checkConnection = setInterval(() => {
          if (!client.isConnected()) {
            if (checkConnection) {
              clearInterval(checkConnection);
              checkConnection = null;
            }
            renderer.cleanup();
            console.error(colorize("red", "\nDaemon disconnected."));
            process.exit(1);
          }
        }, 1000);
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
