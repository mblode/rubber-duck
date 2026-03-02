import { styleText } from "node:util";
import { intro, log, outro } from "@clack/prompts";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { runHealthChecks } from "../health-checks.js";
import type { DoctorCheck } from "../types.js";

function renderCheck(check: DoctorCheck): void {
  const label = styleText("bold", check.name.padEnd(14));
  const message = `${label} ${check.message}`;
  if (check.status === "ok") {
    log.success(message);
  } else if (check.status === "warn") {
    log.warn(message);
  } else {
    log.error(message);
  }
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
      message: "Not running. Run `rubber-duck` to start.",
    });
  }
}

export function registerDoctorCommand(program: Command): void {
  program
    .command("doctor")
    .description("Check system health and dependencies")
    .action(async () => {
      intro("rubber-duck doctor");

      const checks = runHealthChecks("client");
      await fetchDaemonChecks(checks);

      for (const check of checks) {
        renderCheck(check);
      }

      const hasFail = checks.some((c) => c.status === "fail");
      const hasWarn = checks.some((c) => c.status === "warn");

      if (hasFail) {
        outro(styleText("red", "Some checks failed."));
        process.exit(1);
      } else if (hasWarn) {
        outro(styleText("yellow", "Ready with warnings."));
      } else {
        outro(styleText("green", "All checks passed."));
      }
    });
}
