import { homedir } from "node:os";
import { styleText } from "node:util";
import { log, S_STEP_SUBMIT } from "@clack/prompts";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { formatTimestamp } from "../utils.js";

function shortenPath(p: string): string {
  const home = homedir();
  return p.startsWith(home) ? `~${p.slice(home.length)}` : p;
}

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
    // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: Branches handle table header, ANSI-aware padding, and per-row formatting for compact output.
    .action(async (options) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const response = await client.request("sessions", {
          all: options.all ?? false,
        });

        if (!response.ok) {
          log.error(response.error ?? "Unknown error");
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
          log.info("No sessions yet. Run `rubber-duck` to start.");
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
          ...sessions.map((s) => shortenPath(s.workspacePath).length)
        );

        console.log(
          styleText(
            "dim",
            `${"SESSION".padEnd(nameWidth)}  ${"WORKSPACE".padEnd(pathWidth)}  ${"STATUS".padEnd(10)}  LAST ACTIVE`
          )
        );

        for (const s of sessions) {
          // Padding must be calculated from visible width — ANSI codes in the
          // styled marker inflate string length and break padEnd alignment.
          const visibleWidth = s.name.length + (s.isActive ? 2 : 0);
          const trailing = " ".repeat(Math.max(0, nameWidth - visibleWidth));
          const displayName = s.isActive
            ? `${s.name} ${styleText("green", S_STEP_SUBMIT)}${trailing}`
            : s.name.padEnd(nameWidth);

          let status: string;
          if (s.isRunning) {
            status = styleText("green", "running".padEnd(10));
          } else {
            status = styleText("dim", "stopped".padEnd(10));
          }

          const lastActive = formatTimestamp(s.lastActiveAt);

          console.log(
            `${displayName}  ${shortenPath(s.workspacePath).padEnd(pathWidth)}  ${status}  ${styleText("dim", lastActive)}`
          );
        }

        client.close();
      } catch (err) {
        log.error(err instanceof Error ? err.message : String(err));
        process.exit(1);
      }
    });
}
