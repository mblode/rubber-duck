import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";

export function registerAbortCommand(program: Command): void {
  program
    .command("abort [session]")
    .description("Abort the current agent operation")
    .action(async (sessionArg?: string) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const params: Record<string, unknown> = {};
        if (sessionArg) {
          params.sessionId = sessionArg;
        }

        const response = await client.request("abort", params);

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { sessionName } = response.data as {
          sessionId: string;
          sessionName: string;
        };

        console.log(`Aborted: ${styleText("yellow", sessionName)}`);

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
