import { execSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import {
  CONFIG_PATH,
  LOG_PATH,
  PI_BINARY,
  PI_BINARY_OVERRIDE_ENV,
  PI_DEFAULT_THINKING,
  PI_MODEL_OVERRIDE_ENV,
  PI_PROVIDER_OVERRIDE_ENV,
  PI_THINKING_OVERRIDE_ENV,
  resolveDefaultPiModel,
  resolveDefaultPiProvider,
  SOCKET_PATH,
} from "./constants.js";
import type { DoctorCheck } from "./types.js";

export interface DaemonExtras {
  pid: number;
  runningSessionCount: number;
  uptimeMs: number;
}

type HealthCheckContext = "client" | "daemon";

function resolvePiAgentCoreVersion(): string | null {
  try {
    const resolvedPiBinary = realpathSync(PI_BINARY);
    const distDir = dirname(resolvedPiBinary);
    const piCliPackageRoot = dirname(distDir);
    const corePackagePath = join(
      piCliPackageRoot,
      "..",
      "pi-agent-core",
      "package.json"
    );
    if (!existsSync(corePackagePath)) {
      return null;
    }

    const raw = readFileSync(corePackagePath, "utf-8");
    const pkg = JSON.parse(raw) as { name?: unknown; version?: unknown };
    if (pkg.name !== "@mariozechner/pi-agent-core") {
      return null;
    }

    return typeof pkg.version === "string" ? pkg.version : null;
  } catch {
    return null;
  }
}

function addDaemonStatusCheck(
  checks: DoctorCheck[],
  context: HealthCheckContext,
  extras?: DaemonExtras
): void {
  if (context !== "daemon" || !extras) {
    return;
  }
  checks.push({
    name: "daemon",
    status: "ok",
    message: `Running (pid ${extras.pid}, uptime ${Math.floor(extras.uptimeMs / 1000)}s)`,
  });
}

function addPiBinaryCheck(checks: DoctorCheck[]): void {
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
}

function resolvePiModelSource(model: string | null): string {
  if (process.env[PI_MODEL_OVERRIDE_ENV]) {
    return `${PI_MODEL_OVERRIDE_ENV} env var`;
  }
  if (model) {
    return "API key auto-detect";
  }
  return "Pi default";
}

function resolvePiProviderSource(provider: string | null): string {
  if (process.env[PI_PROVIDER_OVERRIDE_ENV]) {
    return `${PI_PROVIDER_OVERRIDE_ENV} env var`;
  }
  if (provider) {
    return "API key auto-detect";
  }
  return "Pi default";
}

function addPiModelCheck(checks: DoctorCheck[]): void {
  const model = resolveDefaultPiModel();
  const provider = resolveDefaultPiProvider();
  const thinking =
    process.env[PI_THINKING_OVERRIDE_ENV]?.trim() ?? PI_DEFAULT_THINKING;
  const modelSource = resolvePiModelSource(model);
  const providerSource = resolvePiProviderSource(provider);
  checks.push({
    name: "pi_model",
    status: "ok",
    message:
      `${provider ?? "Pi default"}/${model ?? "Pi default"}  ` +
      `thinking:${thinking}  ` +
      `(model:${modelSource}, provider:${providerSource})`,
  });
}

function addPiAgentCoreCheck(
  checks: DoctorCheck[],
  context: HealthCheckContext
): void {
  if (context !== "daemon") {
    return;
  }
  const piAgentCoreVersion = resolvePiAgentCoreVersion();
  if (piAgentCoreVersion) {
    checks.push({
      name: "pi_agent_core",
      status: "ok",
      message: `@mariozechner/pi-agent-core ${piAgentCoreVersion}`,
    });
    return;
  }
  checks.push({
    name: "pi_agent_core",
    status: "fail",
    message:
      "Could not resolve @mariozechner/pi-agent-core from the configured pi binary",
  });
}

function addSocketCheck(
  checks: DoctorCheck[],
  context: HealthCheckContext
): void {
  if (existsSync(SOCKET_PATH)) {
    checks.push({
      name: "socket",
      status: "ok",
      message: SOCKET_PATH,
    });
    return;
  }
  if (context === "daemon") {
    checks.push({
      name: "socket",
      status: "fail",
      message: "Socket file missing",
    });
    return;
  }
  checks.push({
    name: "socket",
    status: "warn",
    message: "Socket not found. Run `duck` to start daemon.",
  });
}

function addConfigAndLogChecks(
  checks: DoctorCheck[],
  context: HealthCheckContext
): void {
  if (context !== "daemon") {
    return;
  }
  const hasConfig = existsSync(CONFIG_PATH);
  checks.push({
    name: "config",
    status: hasConfig ? "ok" : "warn",
    message: hasConfig
      ? CONFIG_PATH
      : "Config file missing, will be created on restart",
  });

  const hasLog = existsSync(LOG_PATH);
  checks.push({
    name: "log",
    status: hasLog ? "ok" : "warn",
    message: hasLog ? LOG_PATH : "Log file not created yet",
  });
}

function addProvidersCheck(checks: DoctorCheck[]): void {
  const providers: string[] = [];
  if (process.env.OPENAI_API_KEY) {
    providers.push("openai");
  }
  if (process.env.ANTHROPIC_API_KEY) {
    providers.push("anthropic");
  }

  if (providers.length === 0) {
    checks.push({
      name: "providers",
      status: "warn",
      message: "No API keys found. Set OPENAI_API_KEY or use `pi /login`",
    });
    return;
  }

  checks.push({
    name: "providers",
    status: "ok",
    message: providers.join(", "),
  });
}

function addAppCheck(checks: DoctorCheck[], context: HealthCheckContext): void {
  if (context !== "client") {
    return;
  }
  try {
    execSync('pgrep -x "Rubber Duck"', { encoding: "utf-8" });
    checks.push({
      name: "app",
      status: "ok",
      message: "Rubber Duck.app running",
    });
  } catch {
    checks.push({
      name: "app",
      status: "warn",
      message: "Rubber Duck.app not running (voice features unavailable)",
    });
  }
}

function addRunningSessionsCheck(
  checks: DoctorCheck[],
  context: HealthCheckContext,
  extras?: DaemonExtras
): void {
  if (context !== "daemon" || !extras) {
    return;
  }
  checks.push({
    name: "sessions",
    status: "ok",
    message: `${extras.runningSessionCount} running`,
  });
}

export function runHealthChecks(
  context: HealthCheckContext,
  extras?: DaemonExtras
): DoctorCheck[] {
  const checks: DoctorCheck[] = [];

  addDaemonStatusCheck(checks, context, extras);
  addPiBinaryCheck(checks);
  addPiModelCheck(checks);
  addPiAgentCoreCheck(checks, context);
  addSocketCheck(checks, context);
  addConfigAndLogChecks(checks, context);
  addProvidersCheck(checks);
  addAppCheck(checks, context);
  addRunningSessionsCheck(checks, context, extras);

  return checks;
}
