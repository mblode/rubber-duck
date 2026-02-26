import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";

export function registerUseCommand(program: Command): void {
  program
    .command("use <session>")
    .description("Set the active voice session")
    .action(async (sessionArg: string) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const response = await client.request("use", {
          sessionId: sessionArg,
        });

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { sessionName, workspacePath } = response.data as {
          sessionId: string;
          sessionName: string;
          workspacePath: string;
        };

        console.log(
          `Active voice session: ${styleText("cyan", sessionName)} (${styleText("dim", workspacePath)})`
        );

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
