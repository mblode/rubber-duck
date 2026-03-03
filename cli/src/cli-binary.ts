// Binary entry point — routes to daemon or CLI using an async IIFE.
// Written without top-level await or static imports so esbuild can output CJS
// (required by @yao-pkg/pkg for the standalone binary).
// CJS require() is intentional here — static ESM imports would break CJS output.
const { appendFileSync } = require("node:fs") as typeof import("node:fs");
const { LOG_PATH } = require("./constants.js") as typeof import("./constants.js");

const invokedAs = process.argv[1] ?? "";
const isBinaryDaemonMode =
  invokedAs.endsWith("duck-daemon") ||
  invokedAs.endsWith("--daemon") || // pkg bootstrap: path.resolve("--daemon") → "/cwd/--daemon"
  process.argv[0]?.endsWith("duck-daemon") ||
  process.argv[2] === "--daemon"; // npm dev mode: node spawns daemon.js directly

if (isBinaryDaemonMode) {
  if (process.argv[2] === "--daemon") {
    process.argv.splice(2, 1);
  }
  // Prevent the daemon module's own top-level main() call from double-starting.
  process.env._RUBBER_DUCK_SKIP_AUTO_START = "1";
  (async () => {
    const { main } = await import("./daemon/main.js");
    await main();
  })().catch((err: unknown) => {
    try {
      appendFileSync(
        LOG_PATH,
        `${new Date().toISOString()} Daemon failed to start (cli-binary): ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`,
      );
    } catch {}
    console.error("Daemon failed to start:", err);
    process.exit(1);
  });
} else {
  (async () => {
    const { Command } = await import("commander");
    const { registerDefaultAction } = await import("./commands/default.js");
    const { registerDoctorCommand } = await import("./commands/doctor.js");
    const { registerSayCommand } = await import("./commands/say.js");
    const { registerSessionsCommand } = await import("./commands/sessions.js");

    const program = new Command();
    program
      .name("duck")
      .description("Voice-first coding companion CLI")
      .version("0.0.1");

    for (const fn of [
      registerDefaultAction,
      registerSayCommand,
      registerSessionsCommand,
      registerDoctorCommand,
    ] as const) {
      fn(program);
    }

    program.parse();
  })().catch((err: unknown) => {
    console.error(err);
    process.exit(1);
  });
}
