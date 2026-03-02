import { existsSync } from "node:fs";
import { log } from "@clack/prompts";
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

export function registerDefaultAction(program: Command): void {
  program
    .argument("[path]", "Workspace path (defaults to current directory)")
    .action(async (pathArg?: string) => {
      const color = defaultColorEnabled();
      let client: DaemonClient | null = null;

      try {
        if (
          pathArg &&
          REMOVED_COMMANDS.has(pathArg) &&
          !pathArg.includes("/") &&
          !existsSync(resolveWorkspacePath(pathArg))
        ) {
          log.warn(
            `\`${pathArg}\` was removed. Use \`rubber-duck\` to attach+stream and \`rubber-duck say ...\` to send prompts.`
          );
          process.exit(1);
        }

        await ensureDaemon();
        client = await DaemonClient.connect();

        const attachResponse = await client.request("attach", {
          path: resolveWorkspacePath(pathArg),
        });

        if (!attachResponse.ok) {
          log.error(attachResponse.error ?? "Failed to attach workspace");
          client.close();
          process.exit(1);
        }

        const { session } = attachResponse.data as {
          session: { id: string; name: string };
          workspace: { id: string; path: string };
        };

        await startFollowStream(client, session.id, {
          color,
          json: false,
          showThinking: false,
          verbose: false,
        });
      } catch (err) {
        client?.close();
        log.error(`${err instanceof Error ? err.message : String(err)}`);
        process.exit(1);
      }
    });
}
