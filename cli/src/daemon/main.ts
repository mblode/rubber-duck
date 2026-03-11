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
  LOG_PATH,
  PID_PATH,
  SESSIONS_DIR,
  SOCKET_PATH,
} from "../constants.js";
import type { DaemonRequest } from "../types.js";
import { ClientRegistry } from "./client-registry.js";
import { DaemonConfigStore } from "./config-store.js";
import { EventBus } from "./event-bus.js";
import { HealthMonitor } from "./health.js";
import { MetadataStore } from "./metadata-store.js";
import { PiProcessManager } from "./pi-process-manager.js";
import { RemoteControlManager } from "./remote-control.js";
import { RequestHandler } from "./request-handler.js";
import { SocketServer } from "./socket-server.js";

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

export async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const argsVerbose = args.includes("--verbose");

  if (existsSync(PID_PATH)) {
    try {
      const pid = Number.parseInt(readFileSync(PID_PATH, "utf-8").trim(), 10);
      process.kill(pid, 0);
      if (argsVerbose) {
        console.error(`Daemon already running (pid ${pid})`);
      }
      process.exit(0);
    } catch {
      try {
        unlinkSync(PID_PATH);
      } catch {
        // ignore stale pid cleanup failure
      }
    }
  }

  mkdirSync(APP_SUPPORT, { recursive: true });
  mkdirSync(SESSIONS_DIR, { recursive: true });

  const configStore = new DaemonConfigStore();
  const verbose = argsVerbose || configStore.getConfig().logToStderr;

  logDaemon(`Daemon boot (pid ${process.pid})`, verbose);

  const metadataStore = new MetadataStore();
  const eventBus = new EventBus();
  const clientRegistry = new ClientRegistry();
  const processManager = new PiProcessManager(eventBus);
  const socketServer = new SocketServer(clientRegistry);
  const remoteControlManager = new RemoteControlManager(
    configStore,
    clientRegistry,
    (message: string) => logDaemon(message, verbose)
  );
  const requestHandler = new RequestHandler(
    metadataStore,
    processManager,
    eventBus,
    clientRegistry,
    remoteControlManager
  );
  const healthMonitor = new HealthMonitor(
    processManager,
    eventBus,
    metadataStore
  );

  socketServer.setRequestHandler((clientId, request) =>
    requestHandler.handle(clientId, request)
  );
  socketServer.setDisconnectHandler((clientId) =>
    requestHandler.handleDisconnect(clientId)
  );

  remoteControlManager.setRequestHandler(
    (clientId: string, request: DaemonRequest) =>
      requestHandler.handle(clientId, request)
  );
  remoteControlManager.setDisconnectHandler((clientId: string) =>
    requestHandler.handleDisconnect(clientId)
  );

  await socketServer.start();
  await remoteControlManager.start();

  try {
    writeFileSync(PID_PATH, String(process.pid), { flag: "wx" });
  } catch (err) {
    const error = err as NodeJS.ErrnoException;
    if (error.code === "EEXIST") {
      logDaemon(
        "PID file already exists after startup; another daemon instance won the race",
        verbose
      );
      await remoteControlManager.stop();
      await socketServer.stop();
      process.exit(0);
    }
    throw err;
  }

  healthMonitor.start();

  logDaemon(
    `Daemon started (pid ${process.pid}, socket ${SOCKET_PATH})`,
    verbose
  );

  async function shutdown(): Promise<void> {
    logDaemon("Shutting down...", verbose);
    healthMonitor.stop();
    await processManager.killAll();
    await remoteControlManager.stop();
    await socketServer.stop();
    clientRegistry.closeAll();
    eventBus.clear();
    try {
      unlinkSync(PID_PATH);
    } catch {
      // ignore
    }
    logDaemon("Shutdown complete", verbose);
    process.exit(0);
  }

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  process.stdin?.resume();
}

if (process.env._RUBBER_DUCK_SKIP_AUTO_START !== "1") {
  main().catch((err) => {
    appendDaemonLog(
      `Daemon failed to start: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`
    );
    console.error("Daemon failed to start:", err);
    process.exit(1);
  });
}
