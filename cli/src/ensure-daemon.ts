import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  DAEMON_PING_TIMEOUT_MS,
  DAEMON_STARTUP_TIMEOUT_MS,
  PID_PATH,
  SOCKET_PATH,
} from "./constants.js";

function isDaemonReachable(): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const socket = createConnection({ path: SOCKET_PATH });
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, DAEMON_PING_TIMEOUT_MS);

    socket.on("connect", () => {
      clearTimeout(timer);
      socket.destroy();
      resolve(true);
    });

    socket.on("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function ensureDaemon(): Promise<void> {
  // Quick check — is daemon already running?
  if (await isDaemonReachable()) {
    return;
  }

  // Check PID file for stale process
  if (existsSync(PID_PATH)) {
    try {
      const pid = Number.parseInt(readFileSync(PID_PATH, "utf-8").trim(), 10);
      process.kill(pid, 0);
      // Process exists but socket not ready — wait a bit
      await sleep(500);
      if (await isDaemonReachable()) {
        return;
      }
    } catch {
      // PID file is stale
    }
  }

  // Spawn daemon
  const currentFile = fileURLToPath(import.meta.url);
  const distDir = dirname(currentFile);
  const daemonPath = join(distDir, "daemon.js");

  const child = spawn(process.execPath, [daemonPath, "--verbose"], {
    detached: true,
    stdio: "ignore",
    env: { ...process.env },
  });
  child.unref();

  // Poll with exponential backoff until daemon is reachable
  const delays = [100, 200, 400, 800, 1500];
  let elapsed = 0;

  for (const delay of delays) {
    await sleep(delay);
    elapsed += delay;

    if (await isDaemonReachable()) {
      return;
    }

    if (elapsed >= DAEMON_STARTUP_TIMEOUT_MS) {
      break;
    }
  }

  throw new Error("Daemon failed to start. Run `duck doctor` for diagnostics.");
}
