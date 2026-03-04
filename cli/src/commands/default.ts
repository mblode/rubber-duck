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

function isRemovedCommandToken(pathArg: string | undefined): boolean {
  return (
    !!pathArg &&
    REMOVED_COMMANDS.has(pathArg) &&
    !pathArg.includes("/") &&
    !existsSync(resolveWorkspacePath(pathArg))
  );
}

async function maybeAutoStartVoice(
  client: DaemonClient,
  sessionId: string
): Promise<void> {
  const interactive =
    (process.stdin.isTTY ?? false) && (process.stdout.isTTY ?? false);
  if (!interactive) {
    return;
  }

  const maxAttempts = 12;
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const voiceStartResponse = await client.request("voice_start", {
      sessionId,
    });
    if (!voiceStartResponse.ok) {
      return;
    }

    const data = (voiceStartResponse.data ?? {}) as {
      reason?: string;
      started?: boolean;
    };
    if (data.started === true || data.reason !== "voice_not_connected") {
      return;
    }

    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }

  log.info(
    "Rubber Duck app is not connected. Press Option+D in the app to start voice."
  );
}

export function registerDefaultAction(program: Command): void {
  program
    .argument("[path]", "Workspace path (defaults to current directory)")
    .action(async (pathArg?: string) => {
      const color = defaultColorEnabled();
      let client: DaemonClient | null = null;

      try {
        if (isRemovedCommandToken(pathArg)) {
          log.warn(
            `\`${pathArg}\` was removed. Use \`duck\` to attach+stream and \`duck say ...\` to send prompts.`
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

        await maybeAutoStartVoice(client, session.id);

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
