import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_SUPPORT_OVERRIDE_ENV = "RUBBER_DUCK_APP_SUPPORT";

export function resolveAppSupport(options?: {
  env?: NodeJS.ProcessEnv;
  exists?: (path: string) => boolean;
  homeDir?: string;
}): string {
  const env = options?.env ?? process.env;
  const homeDir = options?.homeDir ?? homedir();
  const pathExists = options?.exists ?? existsSync;
  const override = env[APP_SUPPORT_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }

  const standardPath = join(
    homeDir,
    "Library",
    "Application Support",
    "RubberDuck"
  );
  if (pathExists(standardPath)) {
    return standardPath;
  }

  const legacyContainerPath = join(
    homeDir,
    "Library",
    "Containers",
    "co.blode.rubber-duck",
    "Data",
    "Library",
    "Application Support",
    "RubberDuck"
  );
  if (pathExists(legacyContainerPath)) {
    return legacyContainerPath;
  }

  return standardPath;
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
  return join(tmpdir(), `duck-${suffix}.sock`);
}

export const SOCKET_PATH = resolveSocketPath();
export const SESSIONS_DIR = join(APP_SUPPORT, "pi-sessions");
export const METADATA_PATH = join(APP_SUPPORT, "metadata.json");
export const CONFIG_PATH = join(APP_SUPPORT, "config.json");
export const PID_PATH = join(APP_SUPPORT, "duck-daemon.pid");
export const LOG_PATH = join(APP_SUPPORT, "duck-daemon.log");
export const REMOTE_AUTH_TOKEN_PATH = join(APP_SUPPORT, "remote-auth-token");
export const REMOTE_WS_PATH = "/ws";
export const DEFAULT_REMOTE_HOST = "0.0.0.0";
export const DEFAULT_REMOTE_PORT = 43_111;

export const METADATA_VERSION = 1;
export const DEFAULT_SESSION_PREFIX = "duck";
export const PI_BINARY_OVERRIDE_ENV = "RUBBER_DUCK_PI_BINARY";
export const PI_MODEL_OVERRIDE_ENV = "RUBBER_DUCK_PI_MODEL";
export const PI_PROVIDER_OVERRIDE_ENV = "RUBBER_DUCK_PI_PROVIDER";
export const PI_THINKING_OVERRIDE_ENV = "RUBBER_DUCK_PI_THINKING";
export const PI_DEFAULT_THINKING = "off";
export const REMOTE_ENABLED_OVERRIDE_ENV = "RUBBER_DUCK_REMOTE_ENABLED";
export const REMOTE_HOST_OVERRIDE_ENV = "RUBBER_DUCK_REMOTE_HOST";
export const REMOTE_PORT_OVERRIDE_ENV = "RUBBER_DUCK_REMOTE_PORT";
export const REMOTE_TOKEN_OVERRIDE_ENV = "RUBBER_DUCK_REMOTE_TOKEN";
export const REMOTE_TLS_CERT_PATH_OVERRIDE_ENV =
  "RUBBER_DUCK_REMOTE_TLS_CERT_PATH";
export const REMOTE_TLS_KEY_PATH_OVERRIDE_ENV =
  "RUBBER_DUCK_REMOTE_TLS_KEY_PATH";
export const DAEMON_REMOTE_URL_ENV = "RUBBER_DUCK_DAEMON_URL";
export const DAEMON_REMOTE_TOKEN_ENV = "RUBBER_DUCK_DAEMON_TOKEN";

function resolvePiBinary(): string {
  const override = process.env[PI_BINARY_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }

  try {
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
  } catch {
    // import.meta.url unavailable in standalone binary — fall through to PATH
  }

  return "pi";
}

export const PI_BINARY = resolvePiBinary();
export const DAEMON_PING_TIMEOUT_MS = 500;
export const DAEMON_STARTUP_TIMEOUT_MS = 3000;
export const PI_COMMAND_TIMEOUT_MS = 30_000;
export const HEALTH_CHECK_INTERVAL_MS = 30_000;
export const REMOTE_CONTROL_DEFAULT_HOST = DEFAULT_REMOTE_HOST;
export const REMOTE_CONTROL_DEFAULT_PORT = DEFAULT_REMOTE_PORT;

const DEFAULT_PI_MODEL = "gpt-4o-mini";
const DEFAULT_PI_PROVIDER = "openai";

export const PI_TOOLS = [
  "read",
  "bash",
  "edit",
  "write",
  "grep",
  "find",
  "ls",
] as const;

/**
 * Resolves the Pi model to use for coding sessions.
 * Priority: RUBBER_DUCK_PI_MODEL env var → gpt-4o-mini (if OPENAI_API_KEY set) → null (Pi default)
 */
export function resolveDefaultPiModel(
  env: NodeJS.ProcessEnv = process.env
): string | null {
  const override = env[PI_MODEL_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }
  if (env.OPENAI_API_KEY) {
    return DEFAULT_PI_MODEL;
  }
  return null;
}

/**
 * Resolves the Pi provider to use for coding sessions.
 * Priority: RUBBER_DUCK_PI_PROVIDER env var → openai (if OPENAI_API_KEY set) → null (Pi default)
 *
 * If RUBBER_DUCK_PI_MODEL includes a provider prefix (for example "openai/gpt-4o-mini"),
 * provider selection is considered explicit and no default provider is forced.
 */
export function resolveDefaultPiProvider(
  env: NodeJS.ProcessEnv = process.env
): string | null {
  const override = env[PI_PROVIDER_OVERRIDE_ENV]?.trim();
  if (override) {
    return override;
  }

  const modelOverride = env[PI_MODEL_OVERRIDE_ENV]?.trim();
  if (modelOverride?.includes("/")) {
    return null;
  }

  if (env.OPENAI_API_KEY) {
    return DEFAULT_PI_PROVIDER;
  }

  return null;
}
