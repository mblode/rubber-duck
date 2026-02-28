import { existsSync } from "node:fs";
import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { defaultColorEnabled } from "../renderer/colors.js";
import { resolveWorkspacePath } from "../utils.js";
import { startFollowStream } from "./follow.js";

const REMOVED_COMMANDS = new Set([
  "follow",
  "attach",
  "new",
  "use",
  "abort",
  "export",
]);

function createColorize(color: boolean) {
  return (format: Parameters<typeof styleText>[0], value: string): string =>
    color ? styleText(format, value) : value;
}

export function registerDefaultAction(program: Command): void {
  program
    .argument("[path]", "Workspace path (defaults to current directory)")
    .action(async (pathArg?: string) => {
      const color = defaultColorEnabled();
      const colorize = createColorize(color);
      let client: DaemonClient | null = null;

      try {
        if (
          pathArg &&
          REMOVED_COMMANDS.has(pathArg) &&
          !pathArg.includes("/") &&
          !existsSync(resolveWorkspacePath(pathArg))
        ) {
          console.error(
            colorize(
              "yellow",
              `\`${pathArg}\` was removed. Use \`duck\` to attach+stream and \`duck say ...\` to send prompts.`
            )
          );
          process.exit(1);
        }

        await ensureDaemon();
        client = await DaemonClient.connect();

        const attachResponse = await client.request("attach", {
          path: resolveWorkspacePath(pathArg),
        });

        if (!attachResponse.ok) {
          console.error(colorize("red", `Error: ${attachResponse.error}`));
          client.close();
          process.exit(1);
        }

        const { workspace, session } = attachResponse.data as {
          session: { id: string; name: string };
          workspace: { id: string; path: string };
        };

        console.log(
          `Attached: ${colorize("bold", workspace.path)} (session ${colorize("cyan", session.name)})`
        );

        await startFollowStream(client, session.id, {
          color,
          json: false,
          showThinking: false,
          verbose: false,
        });
      } catch (err) {
        client?.close();
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
