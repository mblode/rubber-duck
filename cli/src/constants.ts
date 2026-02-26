import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const APP_SUPPORT_OVERRIDE_ENV = "RUBBER_DUCK_APP_SUPPORT";

function resolveAppSupport(): string {
  const override = process.env[APP_SUPPORT_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }

  const sandboxPath = join(
    homedir(),
    "Library",
    "Containers",
    "co.blode.rubber-duck",
    "Data",
    "Library",
    "Application Support",
    "RubberDuck"
  );
  if (existsSync(sandboxPath)) {
    return sandboxPath;
  }

  return join(homedir(), "Library", "Application Support", "RubberDuck");
}

export const APP_SUPPORT = resolveAppSupport();
const UNIX_SOCKET_PATH_MAX = 104;

function resolveSocketPath(): string {
  const preferredPath = join(APP_SUPPORT, "daemon.sock");
  if (preferredPath.length < UNIX_SOCKET_PATH_MAX) {
    return preferredPath;
  }

  const suffix = createHash("sha256")
    .update(APP_SUPPORT)
    .digest("hex")
    .slice(0, 12);
  return join(tmpdir(), `rubber-duck-${suffix}.sock`);
}

export const SOCKET_PATH = resolveSocketPath();
export const SESSIONS_DIR = join(APP_SUPPORT, "pi-sessions");
export const METADATA_PATH = join(APP_SUPPORT, "metadata.json");
export const CONFIG_PATH = join(APP_SUPPORT, "config.json");
export const PID_PATH = join(APP_SUPPORT, "duck-daemon.pid");
export const LOG_PATH = join(APP_SUPPORT, "duck-daemon.log");

export const METADATA_VERSION = 1;
export const DEFAULT_SESSION_PREFIX = "duck";
export const PI_BINARY_OVERRIDE_ENV = "RUBBER_DUCK_PI_BINARY";

function resolvePiBinary(): string {
  const override = process.env[PI_BINARY_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }

  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const packageRoot = join(moduleDir, "..");
  const localPiBinary = join(
    packageRoot,
    "node_modules",
    ".bin",
    process.platform === "win32" ? "pi.cmd" : "pi"
  );
  if (existsSync(localPiBinary)) {
    return localPiBinary;
  }

  return "pi";
}

export const PI_BINARY = resolvePiBinary();
export const DAEMON_PING_TIMEOUT_MS = 500;
export const DAEMON_STARTUP_TIMEOUT_MS = 3000;
export const PI_COMMAND_TIMEOUT_MS = 30_000;
export const HEALTH_CHECK_INTERVAL_MS = 30_000;
