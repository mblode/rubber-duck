import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { runHealthChecks } from "../health-checks.js";
import type { DoctorCheck } from "../types.js";

function statusIcon(status: DoctorCheck["status"]): string {
  if (status === "ok") {
    return styleText("green", "ok");
  }
  if (status === "warn") {
    return styleText("yellow", "warn");
  }
  return styleText("red", "fail");
}

function formatCheck(check: DoctorCheck): string {
  const name = check.name.padEnd(12);
  return `  ${name} ${statusIcon(check.status).padEnd(14)}  ${check.message}`;
}

function mergeDaemonChecks(
  checks: DoctorCheck[],
  daemonChecks: DoctorCheck[]
): void {
  for (const dc of daemonChecks) {
    const idx = checks.findIndex((c) => c.name === dc.name);
    if (idx >= 0) {
      checks[idx] = dc;
    } else {
      checks.push(dc);
    }
  }
}

async function fetchDaemonChecks(checks: DoctorCheck[]): Promise<void> {
  try {
    const client = await DaemonClient.connect(2000);
    const response = await client.request("doctor", {});
    client.close();

    if (response.ok && response.data) {
      const daemonChecks = (response.data as { checks: DoctorCheck[] }).checks;
      mergeDaemonChecks(checks, daemonChecks);
    }
  } catch {
    checks.unshift({
      name: "daemon",
      status: "warn",
      message: "Not running. Run `duck` to start.",
    });
  }
}

export function registerDoctorCommand(program: Command): void {
  program
    .command("doctor")
    .description("Check system health and dependencies")
    .action(async () => {
      console.log(styleText("bold", "duck doctor\n"));

      const checks = runHealthChecks("client");
      await fetchDaemonChecks(checks);

      for (const check of checks) {
        console.log(formatCheck(check));
      }

      if (checks.some((c) => c.status === "fail")) {
        process.exit(1);
      }
    });
}
