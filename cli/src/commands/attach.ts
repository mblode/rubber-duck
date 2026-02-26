import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";
import { resolveWorkspacePath } from "../utils.js";

export function registerAttachCommand(program: Command): void {
  program
    .command("attach [path]")
    .description("Attach a directory as a workspace and start a session")
    .action(async (pathArg?: string) => {
      const absPath = resolveWorkspacePath(pathArg);

      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();
        const response = await client.request("attach", { path: absPath });

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          process.exit(1);
        }

        const { workspace, session } = response.data as {
          workspace: { id: string; path: string };
          session: { id: string; name: string };
        };

        console.log(
          `Attached: ${styleText("bold", workspace.path)} (session ${styleText("cyan", session.name)})`
        );
        console.log(`Use: ${styleText("dim", "duck follow")}`);

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
