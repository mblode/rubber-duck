import { existsSync, readFileSync, writeFileSync } from "node:fs";
import {
  CONFIG_PATH,
  DEFAULT_REMOTE_HOST,
  DEFAULT_REMOTE_PORT,
} from "../constants.js";

export interface RemoteDaemonConfig {
  enabled: boolean;
  host: string;
  port: number;
}

export interface DaemonConfig {
  logToStderr: boolean;
  remote: RemoteDaemonConfig;
  version: number;
}

export const DEFAULT_DAEMON_CONFIG: DaemonConfig = {
  version: 1,
  logToStderr: false,
  remote: {
    enabled: false,
    host: DEFAULT_REMOTE_HOST,
    port: DEFAULT_REMOTE_PORT,
  },
};

export function loadDaemonConfig(): DaemonConfig {
  try {
    if (!existsSync(CONFIG_PATH)) {
      saveDaemonConfig(DEFAULT_DAEMON_CONFIG);
      return { ...DEFAULT_DAEMON_CONFIG };
    }

    const raw = readFileSync(CONFIG_PATH, "utf-8");
    const parsed = JSON.parse(raw) as Partial<DaemonConfig> & {
      remote?: Partial<RemoteDaemonConfig>;
    };
    return {
      version:
        typeof parsed.version === "number"
          ? parsed.version
          : DEFAULT_DAEMON_CONFIG.version,
      logToStderr:
        typeof parsed.logToStderr === "boolean"
          ? parsed.logToStderr
          : DEFAULT_DAEMON_CONFIG.logToStderr,
      remote: {
        enabled:
          typeof parsed.remote?.enabled === "boolean"
            ? parsed.remote.enabled
            : DEFAULT_DAEMON_CONFIG.remote.enabled,
        host:
          typeof parsed.remote?.host === "string" && parsed.remote.host.trim()
            ? parsed.remote.host.trim()
            : DEFAULT_DAEMON_CONFIG.remote.host,
        port:
          typeof parsed.remote?.port === "number" &&
          Number.isInteger(parsed.remote.port)
            ? parsed.remote.port
            : DEFAULT_DAEMON_CONFIG.remote.port,
      },
    };
  } catch {
    saveDaemonConfig(DEFAULT_DAEMON_CONFIG);
    return { ...DEFAULT_DAEMON_CONFIG };
  }
}

export function saveDaemonConfig(config: DaemonConfig): void {
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}
