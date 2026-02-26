import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import {
  APP_SUPPORT,
  CONFIG_PATH,
  LOG_PATH,
  PID_PATH,
  SESSIONS_DIR,
  SOCKET_PATH,
} from "../constants.js";
import { EventBus } from "./event-bus.js";
import { HealthMonitor } from "./health.js";
import { MetadataStore } from "./metadata-store.js";
import { PiProcessManager } from "./pi-process-manager.js";
import { RequestHandler } from "./request-handler.js";
import { SocketServer } from "./socket-server.js";

interface DaemonConfig {
  logToStderr: boolean;
  version: number;
}

const DEFAULT_DAEMON_CONFIG: DaemonConfig = {
  version: 1,
  logToStderr: false,
};

function appendDaemonLog(message: string): void {
  try {
    const line = `${new Date().toISOString()} ${message}\n`;
    appendFileSync(LOG_PATH, line);
  } catch {
    // Logging should never crash the daemon.
  }
}

function logDaemon(message: string, verbose: boolean): void {
  appendDaemonLog(message);
  if (verbose) {
    console.error(message);
  }
}

function loadDaemonConfig(): DaemonConfig {
  try {
    if (!existsSync(CONFIG_PATH)) {
      writeFileSync(
        CONFIG_PATH,
        JSON.stringify(DEFAULT_DAEMON_CONFIG, null, 2)
      );
      return { ...DEFAULT_DAEMON_CONFIG };
    }

    const raw = readFileSync(CONFIG_PATH, "utf-8");
    const parsed = JSON.parse(raw) as Partial<DaemonConfig>;
    const config: DaemonConfig = {
      version:
        typeof parsed.version === "number"
          ? parsed.version
          : DEFAULT_DAEMON_CONFIG.version,
      logToStderr:
        typeof parsed.logToStderr === "boolean"
          ? parsed.logToStderr
          : DEFAULT_DAEMON_CONFIG.logToStderr,
    };

    writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
    return config;
  } catch {
    writeFileSync(CONFIG_PATH, JSON.stringify(DEFAULT_DAEMON_CONFIG, null, 2));
    return { ...DEFAULT_DAEMON_CONFIG };
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const argsVerbose = args.includes("--verbose");

  // Check if daemon is already running
  if (existsSync(PID_PATH)) {
    try {
      const pid = Number.parseInt(readFileSync(PID_PATH, "utf-8").trim(), 10);
      process.kill(pid, 0); // Check if process exists
      if (argsVerbose) {
        console.error(`Daemon already running (pid ${pid})`);
      }
      process.exit(0);
    } catch {
      // PID file is stale, clean up
      try {
        unlinkSync(PID_PATH);
      } catch {
        /* ignore */
      }
    }
  }

  // Ensure directories exist
  mkdirSync(APP_SUPPORT, { recursive: true });
  mkdirSync(SESSIONS_DIR, { recursive: true });
  const config = loadDaemonConfig();
  const verbose = argsVerbose || config.logToStderr;
  logDaemon(`Daemon boot (pid ${process.pid})`, verbose);

  // Initialize components
  const metadataStore = new MetadataStore();
  const eventBus = new EventBus();
  const processManager = new PiProcessManager(eventBus);
  const socketServer = new SocketServer();
  const requestHandler = new RequestHandler(
    metadataStore,
    processManager,
    eventBus,
    socketServer
  );
  const healthMonitor = new HealthMonitor(
    processManager,
    eventBus,
    metadataStore
  );

  // Wire request handler
  socketServer.setRequestHandler((clientId, request) =>
    requestHandler.handle(clientId, request)
  );

  // Start socket server
  await socketServer.start();

  // Write PID file
  writeFileSync(PID_PATH, String(process.pid));

  // Start health monitor
  healthMonitor.start();

  logDaemon(
    `Daemon started (pid ${process.pid}, socket ${SOCKET_PATH})`,
    verbose
  );

  // Graceful shutdown
  async function shutdown(): Promise<void> {
    logDaemon("Shutting down...", verbose);
    healthMonitor.stop();
    await processManager.killAll();
    await socketServer.stop();
    eventBus.clear();
    try {
      unlinkSync(PID_PATH);
    } catch {
      /* ignore */
    }
    logDaemon("Shutdown complete", verbose);
    process.exit(0);
  }

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  // Keep process alive
  process.stdin?.resume();
}

main().catch((err) => {
  appendDaemonLog(
    `Daemon failed to start: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`
  );
  console.error("Daemon failed to start:", err);
  process.exit(1);
});
