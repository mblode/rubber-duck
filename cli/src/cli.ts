import { Command } from "commander";
import { registerAbortCommand } from "./commands/abort.js";
import { registerAttachCommand } from "./commands/attach.js";
import { registerDoctorCommand } from "./commands/doctor.js";
import { registerExportCommand } from "./commands/export.js";
import { registerFollowCommand } from "./commands/follow.js";
import { registerNewCommand } from "./commands/new.js";
import { registerSayCommand } from "./commands/say.js";
import { registerSessionsCommand } from "./commands/sessions.js";
import { registerUseCommand } from "./commands/use.js";

const program = new Command();

program
  .name("duck")
  .description(
    "Voice-first coding companion CLI — attach repos, follow sessions, talk to your code"
  )
  .version("0.0.1");

registerAttachCommand(program);
registerFollowCommand(program);
registerSayCommand(program);
registerSessionsCommand(program);
registerUseCommand(program);
registerNewCommand(program);
registerAbortCommand(program);
registerDoctorCommand(program);
registerExportCommand(program);

program.parse();
