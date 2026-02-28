import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { formatTimestamp } from "../utils.js";

interface SessionInfo {
  id: string;
  isActive: boolean;
  isRunning: boolean;
  lastActiveAt: string;
  name: string;
  workspacePath: string;
}

export function registerSessionsCommand(program: Command): void {
  program
    .command("sessions")
    .description("List sessions")
    .option("--all", "Show sessions for all workspaces")
    .option("--json", "Output as JSON")
    .action(async (options) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const response = await client.request("sessions", {
          all: options.all ?? false,
        });

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { sessions } = response.data as { sessions: SessionInfo[] };

        if (options.json) {
          console.log(JSON.stringify(sessions, null, 2));
          client.close();
          return;
        }

        if (sessions.length === 0) {
          console.log(
            styleText("dim", "No sessions yet. Run `duck` to start.")
          );
          client.close();
          return;
        }

        // Print table header
        const nameWidth = Math.max(
          12,
          ...sessions.map((s) => s.name.length + (s.isActive ? 2 : 0))
        );
        const pathWidth = Math.max(
          12,
          ...sessions.map((s) => s.workspacePath.length)
        );

        console.log(
          styleText(
            "dim",
            `${"SESSION".padEnd(nameWidth)}  ${"WORKSPACE".padEnd(pathWidth)}  ${"STATUS".padEnd(10)}  LAST ACTIVE`
          )
        );

        for (const s of sessions) {
          const name = s.isActive
            ? `${s.name} ${styleText("cyan", "*")}`
            : s.name;
          const displayName = name.padEnd(nameWidth);

          let status: string;
          if (s.isRunning) {
            status = styleText("green", "running".padEnd(10));
          } else {
            status = styleText("dim", "stopped".padEnd(10));
          }

          const lastActive = formatTimestamp(s.lastActiveAt);

          console.log(
            `${displayName}  ${s.workspacePath.padEnd(pathWidth)}  ${status}  ${styleText("dim", lastActive)}`
          );
        }

        client.close();
      } catch (err) {
        console.error(
          styleText(
            "red",
            `Error: ${err instanceof Error ? err.message : String(err)}`
          )
        );
        process.exit(1);
      }
    });
}
