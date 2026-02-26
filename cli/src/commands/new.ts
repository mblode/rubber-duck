import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";

export function registerNewCommand(program: Command): void {
  program
    .command("new")
    .description("Create a new session in the current workspace")
    .option("--name <name>", "Session display name")
    .action(async (options) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const params: Record<string, unknown> = {};
        if (options.name) {
          params.name = options.name;
        }

        const response = await client.request("new", params);

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { sessionName } = response.data as {
          sessionId: string;
          sessionName: string;
        };

        console.log(`Created session: ${styleText("cyan", sessionName)}`);
        console.log(`Use: ${styleText("dim", `duck follow ${sessionName}`)}`);

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
