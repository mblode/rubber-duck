import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { ensureDaemon } from "../ensure-daemon.js";

function resolveSourcePath(
  rawPath: string,
  workspacePath: string | undefined
): string {
  if (isAbsolute(rawPath)) {
    return rawPath;
  }

  const candidates = [
    workspacePath ? join(workspacePath, rawPath) : "",
    join(process.cwd(), rawPath),
    rawPath,
  ].filter((value) => value.length > 0);

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return candidates[0] ?? rawPath;
}

function materializeExportOutput(
  requestedOutPath: string | undefined,
  sourcePath: string | undefined,
  html: string | undefined,
  fallbackPath: string
): string {
  if (!requestedOutPath) {
    return sourcePath ?? fallbackPath;
  }

  const destination = resolve(requestedOutPath);
  mkdirSync(dirname(destination), { recursive: true });

  if (sourcePath && existsSync(sourcePath)) {
    copyFileSync(sourcePath, destination);
    return destination;
  }
  if (typeof html === "string") {
    writeFileSync(destination, html, "utf-8");
    return destination;
  }

  throw new Error(
    "Export data did not include a readable source path or HTML content."
  );
}

export function registerExportCommand(program: Command): void {
  program
    .command("export [session]")
    .description("Export a session to HTML")
    .option("--out <file>", "Output file path")
    .action(async (sessionArg: string | undefined, options) => {
      try {
        await ensureDaemon();
        const client = await DaemonClient.connect();

        const params: Record<string, unknown> = {};
        if (sessionArg) {
          params.sessionId = sessionArg;
        }
        if (options.out) {
          params.outPath = options.out;
        }

        const response = await client.request("export", params);

        if (!response.ok) {
          console.error(styleText("red", `Error: ${response.error}`));
          client.close();
          process.exit(1);
        }

        const { outPath, sessionName, workspacePath, exportData } =
          response.data as {
            sessionId: string;
            sessionName: string;
            workspacePath?: string;
            outPath: string;
            exportData?: { path?: string; html?: string };
          };

        const sourcePath =
          typeof exportData?.path === "string"
            ? resolveSourcePath(exportData.path, workspacePath)
            : undefined;

        const displayPath = materializeExportOutput(
          options.out as string | undefined,
          sourcePath,
          exportData?.html,
          outPath
        );

        console.log(
          `Exported session ${styleText("cyan", sessionName)}: ${styleText("dim", displayPath)}`
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
