// Single-binary mode: when invoked as rubber-duck-daemon (symlink) or with --daemon flag
const invokedAs = process.argv[1] ?? "";
const isBinaryDaemonMode =
  invokedAs.endsWith("rubber-duck-daemon") ||
  process.argv[0]?.endsWith("rubber-duck-daemon") ||
  process.argv[2] === "--daemon";

if (isBinaryDaemonMode) {
  if (process.argv[2] === "--daemon") {
    process.argv.splice(2, 1);
  }
  const { main } = await import("./daemon/main.js");
  await main();
  process.exit(0);
}

import { Command } from "commander";
import { registerDefaultAction } from "./commands/default.js";
import { registerDoctorCommand } from "./commands/doctor.js";
import { registerSayCommand } from "./commands/say.js";
import { registerSessionsCommand } from "./commands/sessions.js";

const program = new Command();

program
  .name("rubber-duck")
  .description("Voice-first coding companion CLI")
  .version("0.0.1");

const commandRegistrations = [
  registerDefaultAction,
  registerSayCommand,
  registerSessionsCommand,
  registerDoctorCommand,
];

for (const registerCommand of commandRegistrations) {
  registerCommand(program);
}

program.parse();
