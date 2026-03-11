import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";
import {
  CONFIG_PATH,
  REMOTE_CONTROL_DEFAULT_HOST,
  REMOTE_CONTROL_DEFAULT_PORT,
  REMOTE_ENABLED_OVERRIDE_ENV,
  REMOTE_HOST_OVERRIDE_ENV,
  REMOTE_PORT_OVERRIDE_ENV,
  REMOTE_TLS_CERT_PATH_OVERRIDE_ENV,
  REMOTE_TLS_KEY_PATH_OVERRIDE_ENV,
} from "../constants.js";

export interface RemoteControlConfig {
  authTokenHash: string | null;
  authTokenSalt: string | null;
  authTokenUpdatedAt: string | null;
  enabled: boolean;
  host: string;
  port: number;
  tlsCertPath: string | null;
  tlsKeyPath: string | null;
}

export interface DaemonConfig {
  logToStderr: boolean;
  remote: RemoteControlConfig;
  version: number;
}

export interface DaemonConfigUpdate {
  logToStderr?: boolean;
  remote?: Partial<RemoteControlConfig>;
  version?: number;
}

const DEFAULT_DAEMON_CONFIG: DaemonConfig = {
  version: 2,
  logToStderr: false,
  remote: {
    enabled: false,
    host: REMOTE_CONTROL_DEFAULT_HOST,
    port: REMOTE_CONTROL_DEFAULT_PORT,
    authTokenHash: null,
    authTokenSalt: null,
    authTokenUpdatedAt: null,
    tlsCertPath: null,
    tlsKeyPath: null,
  },
};

function normalizePort(value: unknown): number {
  if (typeof value === "number" && Number.isInteger(value)) {
    return Math.min(65_535, Math.max(0, value));
  }
  return DEFAULT_DAEMON_CONFIG.remote.port;
}

function normalizeOptionalPath(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeOptionalBoolean(value: string | undefined): boolean | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  if (
    normalized === "1" ||
    normalized === "true" ||
    normalized === "yes" ||
    normalized === "on"
  ) {
    return true;
  }
  if (
    normalized === "0" ||
    normalized === "false" ||
    normalized === "no" ||
    normalized === "off"
  ) {
    return false;
  }

  return null;
}

function normalizeOptionalPort(value: string | undefined): number | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed)) {
    return null;
  }

  return Math.min(65_535, Math.max(0, parsed));
}

function normalizeConfig(
  value: Partial<DaemonConfig> | null | undefined
): DaemonConfig {
  const remoteValue = value?.remote;

  return {
    version:
      typeof value?.version === "number"
        ? value.version
        : DEFAULT_DAEMON_CONFIG.version,
    logToStderr:
      typeof value?.logToStderr === "boolean"
        ? value.logToStderr
        : DEFAULT_DAEMON_CONFIG.logToStderr,
    remote: {
      enabled:
        typeof remoteValue?.enabled === "boolean"
          ? remoteValue.enabled
          : DEFAULT_DAEMON_CONFIG.remote.enabled,
      host:
        typeof remoteValue?.host === "string" &&
        remoteValue.host.trim().length > 0
          ? remoteValue.host.trim()
          : DEFAULT_DAEMON_CONFIG.remote.host,
      port: normalizePort(remoteValue?.port),
      authTokenHash:
        typeof remoteValue?.authTokenHash === "string" &&
        remoteValue.authTokenHash.length > 0
          ? remoteValue.authTokenHash
          : null,
      authTokenSalt:
        typeof remoteValue?.authTokenSalt === "string" &&
        remoteValue.authTokenSalt.length > 0
          ? remoteValue.authTokenSalt
          : null,
      authTokenUpdatedAt:
        typeof remoteValue?.authTokenUpdatedAt === "string" &&
        remoteValue.authTokenUpdatedAt.length > 0
          ? remoteValue.authTokenUpdatedAt
          : null,
      tlsCertPath: normalizeOptionalPath(remoteValue?.tlsCertPath),
      tlsKeyPath: normalizeOptionalPath(remoteValue?.tlsKeyPath),
    },
  };
}

export class DaemonConfigStore {
  private data: DaemonConfig;

  constructor() {
    this.data = this.load();
  }

  private load(): DaemonConfig {
    try {
      if (!existsSync(CONFIG_PATH)) {
        this.saveConfig(DEFAULT_DAEMON_CONFIG);
        return structuredClone(DEFAULT_DAEMON_CONFIG);
      }

      const raw = readFileSync(CONFIG_PATH, "utf-8");
      const parsed = JSON.parse(raw) as Partial<DaemonConfig>;
      const normalized = normalizeConfig(parsed);
      this.saveConfig(normalized);
      return normalized;
    } catch {
      this.saveConfig(DEFAULT_DAEMON_CONFIG);
      return structuredClone(DEFAULT_DAEMON_CONFIG);
    }
  }

  private saveConfig(config: DaemonConfig): void {
    const dir = dirname(CONFIG_PATH);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    const tmpPath = `${CONFIG_PATH}.tmp`;
    writeFileSync(tmpPath, JSON.stringify(config, null, 2));
    renameSync(tmpPath, CONFIG_PATH);
  }

  getConfig(): DaemonConfig {
    return structuredClone(this.data);
  }

  getEffectiveConfig(env: NodeJS.ProcessEnv = process.env): DaemonConfig {
    const enabledOverride = normalizeOptionalBoolean(
      env[REMOTE_ENABLED_OVERRIDE_ENV]
    );
    const hostOverride = env[REMOTE_HOST_OVERRIDE_ENV]?.trim();
    const portOverride = normalizeOptionalPort(env[REMOTE_PORT_OVERRIDE_ENV]);
    const tlsCertPathOverride = normalizeOptionalPath(
      env[REMOTE_TLS_CERT_PATH_OVERRIDE_ENV]
    );
    const tlsKeyPathOverride = normalizeOptionalPath(
      env[REMOTE_TLS_KEY_PATH_OVERRIDE_ENV]
    );

    return normalizeConfig({
      ...this.data,
      remote: {
        ...this.data.remote,
        enabled: enabledOverride ?? this.data.remote.enabled,
        host:
          typeof hostOverride === "string" && hostOverride.length > 0
            ? hostOverride
            : this.data.remote.host,
        port: portOverride ?? this.data.remote.port,
        tlsCertPath: tlsCertPathOverride ?? this.data.remote.tlsCertPath,
        tlsKeyPath: tlsKeyPathOverride ?? this.data.remote.tlsKeyPath,
      },
    });
  }

  updateConfig(updates: DaemonConfigUpdate): DaemonConfig {
    this.data = normalizeConfig({
      ...this.data,
      ...updates,
      remote: {
        ...this.data.remote,
        ...updates.remote,
      },
    });
    this.saveConfig(this.data);
    return this.getConfig();
  }
}
