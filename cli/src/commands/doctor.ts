import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { styleText } from "node:util";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import {
  PI_BINARY,
  PI_BINARY_OVERRIDE_ENV,
  SOCKET_PATH,
} from "../constants.js";
import type { DoctorCheck } from "../types.js";

function localChecks(): DoctorCheck[] {
  const checks: DoctorCheck[] = [];

  // Check Pi binary
  try {
    const version = execSync(`${PI_BINARY} --version 2>/dev/null`, {
      encoding: "utf-8",
    }).trim();
    checks.push({
      name: "pi",
      status: "ok",
      message: `${PI_BINARY} ${version}`,
    });
  } catch {
    checks.push({
      name: "pi",
      status: "fail",
      message: `Pi not found. Install in cli: npm install @mariozechner/pi-coding-agent, install globally: npm install -g @mariozechner/pi-coding-agent, or set ${PI_BINARY_OVERRIDE_ENV}.`,
    });
  }

  // Check providers
  const providerVars = [
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "MISTRAL_API_KEY",
  ];
  const foundProviders = providerVars.filter((v) => process.env[v]);
  if (foundProviders.length > 0) {
    checks.push({
      name: "providers",
      status: "ok",
      message: foundProviders
        .map((v) => v.replace("_API_KEY", "").toLowerCase())
        .join(", "),
    });
  } else {
    checks.push({
      name: "providers",
      status: "warn",
      message: "No API keys found. Set ANTHROPIC_API_KEY or use `pi /login`",
    });
  }

  // Check socket file
  if (existsSync(SOCKET_PATH)) {
    checks.push({ name: "socket", status: "ok", message: SOCKET_PATH });
  } else {
    checks.push({
      name: "socket",
      status: "warn",
      message: "Socket not found. Run `duck attach` to start daemon.",
    });
  }

  // Check RubberDuck.app
  try {
    execSync("pgrep -x RubberDuck", { encoding: "utf-8" });
    checks.push({
      name: "app",
      status: "ok",
      message: "RubberDuck.app running",
    });
  } catch {
    checks.push({
      name: "app",
      status: "warn",
      message: "RubberDuck.app not running (voice features unavailable)",
    });
  }

  return checks;
}

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
      message: "Not running. Run `duck attach` to start.",
    });
  }
}

export function registerDoctorCommand(program: Command): void {
  program
    .command("doctor")
    .description("Check system health and dependencies")
    .action(async () => {
      console.log(styleText("bold", "duck doctor\n"));

      const checks = localChecks();
      await fetchDaemonChecks(checks);

      for (const check of checks) {
        console.log(formatCheck(check));
      }

      if (checks.some((c) => c.status === "fail")) {
        process.exit(1);
      }
    });
}
