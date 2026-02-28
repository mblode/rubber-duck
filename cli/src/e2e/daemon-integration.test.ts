import { type ChildProcess, spawn } from "node:child_process";
import { access, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { DaemonClient } from "../client.js";
import type { DaemonEvent, PiEvent } from "../types.js";

const NUMBER_TWO_REGEX = /2/;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function waitForSocket(
  socketPath: string,
  timeoutMs = 10_000
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      await access(socketPath);
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 200));
    }
  }
  throw new Error(`Socket not ready after ${timeoutMs}ms: ${socketPath}`);
}

function waitForEvent(
  events: PiEvent[],
  type: string,
  timeoutMs = 60_000
): Promise<PiEvent> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      clearInterval(interval);
      reject(
        new Error(
          `Timed out waiting for event "${type}" after ${timeoutMs}ms. ` +
            `Received ${events.length} events: [${events.map((e) => e.type).join(", ")}]`
        )
      );
    }, timeoutMs);

    const interval = setInterval(() => {
      const found = events.find((e) => e.type === type);
      if (found) {
        clearInterval(interval);
        clearTimeout(timer);
        resolve(found);
      }
    }, 200);

    // Check immediately in case event is already collected
    const found = events.find((e) => e.type === type);
    if (found) {
      clearInterval(interval);
      clearTimeout(timer);
      resolve(found);
    }
  });
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

const hasApiKey = Boolean(
  process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY
);

describe.skipIf(!hasApiKey)("duck say E2E — daemon integration", () => {
  let daemonProcess: ChildProcess;
  let tmpDir: string;
  let socketPath: string;

  beforeAll(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), "duck-e2e-"));
    socketPath = join(tmpDir, "daemon.sock");

    // Spawn daemon with isolated app support dir so it creates its socket
    // inside our temp directory. The daemon reads RUBBER_DUCK_APP_SUPPORT
    // at import time via constants.ts → resolveAppSupport().
    daemonProcess = spawn(
      process.execPath,
      [join(process.cwd(), "dist/daemon.js"), "--verbose"],
      {
        env: { ...process.env, RUBBER_DUCK_APP_SUPPORT: tmpDir },
        stdio: ["ignore", "pipe", "pipe"],
        detached: false,
      }
    );

    // Pipe daemon output to stderr for debugging
    daemonProcess.stdout?.on("data", (d: Buffer) =>
      process.stderr.write(`[daemon:out] ${d}`)
    );
    daemonProcess.stderr?.on("data", (d: Buffer) =>
      process.stderr.write(`[daemon:err] ${d}`)
    );

    await waitForSocket(socketPath, 10_000);
  }, 15_000);

  afterAll(async () => {
    if (daemonProcess) {
      daemonProcess.kill("SIGTERM");
      // Give daemon time to clean up
      await new Promise((r) => setTimeout(r, 500));
      if (!daemonProcess.killed) {
        daemonProcess.kill("SIGKILL");
      }
    }
    if (tmpDir) {
      await rm(tmpDir, { recursive: true, force: true });
    }
  });

  it("attach → say → receives agent_end with response", async () => {
    // Connect to isolated daemon using explicit socket path
    const client = await DaemonClient.connect({ socketPath });

    // Attach a temp workspace (use the temp dir itself)
    const attachResp = await client.request("attach", { path: tmpDir });
    expect(attachResp.ok).toBe(true);
    expect(attachResp.data).toBeDefined();

    const sessionId = (attachResp.data as { session: { id: string } }).session
      .id;
    expect(sessionId).toBeTruthy();

    // Follow the session to receive streamed events
    const followResp = await client.request("follow", { sessionId });
    expect(followResp.ok).toBe(true);

    // Collect events as they arrive
    const events: PiEvent[] = [];
    client.onEvent((event: DaemonEvent) => {
      if (
        event.data &&
        typeof event.data === "object" &&
        "type" in event.data
      ) {
        events.push(event.data as PiEvent);
      }
    });

    // Send a simple prompt
    const sayResp = await client.request(
      "say",
      { message: "What is 1+1? Reply with just the number.", sessionId },
      60_000
    );
    expect(sayResp.ok).toBe(true);

    // Wait for agent_end event (the Pi agent finished its turn)
    const agentEnd = await waitForEvent(events, "agent_end", 60_000);
    expect(agentEnd).toBeDefined();
    expect(agentEnd.type).toBe("agent_end");

    // The agent_end event carries a messages array; the response should
    // contain "2" somewhere in the serialised messages.
    const agentEndAny = agentEnd as unknown as { messages?: unknown[] };
    const responseText = JSON.stringify(agentEndAny.messages ?? []);
    expect(responseText).toMatch(NUMBER_TWO_REGEX);

    client.close();
  }, 70_000);
});
