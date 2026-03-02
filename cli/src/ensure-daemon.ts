import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spinner } from "@clack/prompts";
import {
  DAEMON_PING_TIMEOUT_MS,
  DAEMON_STARTUP_TIMEOUT_MS,
  PID_PATH,
  SOCKET_PATH,
} from "./constants.js";

interface EnsureDaemonOptions {
  quiet?: boolean;
}

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

export async function ensureDaemon(
  options: EnsureDaemonOptions = {}
): Promise<void> {
  const quiet = options.quiet ?? false;

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
  const s = quiet ? null : spinner();
  s?.start("Starting daemon...");

  // In a standalone pkg binary, process.execPath is the duck binary itself.
  // Spawn it with --daemon to start the daemon process.
  // In normal npm installation, spawn node with the daemon.js path.
  const isPackaged =
    typeof (process as NodeJS.Process & { pkg?: unknown }).pkg !== "undefined";
  const daemonArgs = isPackaged
    ? ["--daemon", "--verbose"]
    : (() => {
        const currentFile = fileURLToPath(import.meta.url);
        const distDir = dirname(currentFile);
        const daemonPath = join(distDir, "daemon.js");
        return [daemonPath, "--verbose"];
      })();

  const child = spawn(process.execPath, daemonArgs, {
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
      s?.stop();
      return;
    }

    if (elapsed >= DAEMON_STARTUP_TIMEOUT_MS) {
      break;
    }
  }

  s?.stop("Daemon failed to start");
  throw new Error(
    "Daemon failed to start. Run `duck doctor` for diagnostics."
  );
}
