import { Command } from "commander";
import { registerDefaultAction } from "./commands/default.js";
import { registerDoctorCommand } from "./commands/doctor.js";
import { registerSayCommand } from "./commands/say.js";
import { registerSessionsCommand } from "./commands/sessions.js";

const program = new Command();

program
  .name("duck")
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
