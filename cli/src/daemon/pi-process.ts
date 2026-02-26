import { type ChildProcess, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import {
  PI_BINARY,
  PI_COMMAND_TIMEOUT_MS,
  SESSIONS_DIR,
} from "../constants.js";
import type { PiEvent, PiRpcRequest, PiRpcResponse } from "../types.js";
import { generateId } from "../utils.js";

interface PendingRequest {
  command: string;
  reject: (error: Error) => void;
  resolve: (response: PiRpcResponse) => void;
  timer: ReturnType<typeof setTimeout>;
}

export type PiEventHandler = (event: PiEvent) => void;

export class PiProcess {
  private readonly process: ChildProcess;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly eventHandlers: PiEventHandler[] = [];
  private alive = true;
  private exitCode: number | null = null;
  readonly sessionId: string;

  constructor(
    workspacePath: string,
    options: {
      sessionId: string;
      sessionFile?: string;
      continueSession?: boolean;
      sessionDir?: string;
    }
  ) {
    this.sessionId = options.sessionId;
    const args = [
      "--mode",
      "rpc",
      "--session-dir",
      options.sessionDir ?? SESSIONS_DIR,
    ];
    if (options.sessionFile) {
      args.push("--session", options.sessionFile);
    }
    if (options.continueSession) {
      args.push("-c");
    }

    this.process = spawn(PI_BINARY, args, {
      cwd: workspacePath,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
    });

    this.process.on("exit", (code) => {
      this.alive = false;
      this.exitCode = code;
      // Reject all pending requests
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`Pi process exited with code ${code}`));
        this.pending.delete(id);
      }
    });

    this.process.on("error", (err) => {
      this.alive = false;
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(err);
        this.pending.delete(id);
      }
    });

    // Parse stdout as NDJSON
    if (this.process.stdout) {
      const rl = createInterface({ input: this.process.stdout });
      rl.on("line", (line) => {
        if (!line.trim()) {
          return;
        }
        try {
          const msg = JSON.parse(line) as PiEvent | PiRpcResponse;
          if (msg.type === "response") {
            this.handleResponse(msg as PiRpcResponse);
          } else {
            // It's an event
            const event = msg as PiEvent;
            for (const handler of this.eventHandlers) {
              try {
                handler(event);
              } catch {
                // Don't let handler errors crash the process
              }
            }
          }
        } catch {
          // Ignore unparseable lines (e.g., Pi startup messages)
        }
      });
    }
  }

  private handleResponse(response: PiRpcResponse): void {
    if (response.id) {
      const pending = this.pending.get(response.id);
      if (pending) {
        clearTimeout(pending.timer);
        this.pending.delete(response.id);
        pending.resolve(response);
      }
      return;
    }

    if (!response.command) {
      return;
    }

    for (const [id, pending] of this.pending) {
      if (pending.command === response.command) {
        clearTimeout(pending.timer);
        this.pending.delete(id);
        pending.resolve(response);
        return;
      }
    }
  }

  sendCommand(
    command: string,
    params?: Record<string, unknown>
  ): Promise<PiRpcResponse> {
    if (!this.alive) {
      throw new Error(
        `Pi process is not running (exit code: ${this.exitCode})`
      );
    }

    const id = generateId();
    const request: PiRpcRequest = { id, type: command, ...params };
    const line = `${JSON.stringify(request)}\n`;

    return new Promise<PiRpcResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(
          new Error(
            `Pi command "${command}" timed out after ${PI_COMMAND_TIMEOUT_MS}ms`
          )
        );
      }, PI_COMMAND_TIMEOUT_MS);

      this.pending.set(id, { command, resolve, reject, timer });

      if (!this.process.stdin?.write(line)) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new Error("Failed to write to Pi process stdin"));
      }
    });
  }

  sendUntracked(command: string, params?: Record<string, unknown>): void {
    if (!this.alive) {
      throw new Error(
        `Pi process is not running (exit code: ${this.exitCode})`
      );
    }

    const request: PiRpcRequest = { type: command, ...params };
    const line = `${JSON.stringify(request)}\n`;
    if (!this.process.stdin?.write(line)) {
      throw new Error("Failed to write to Pi process stdin");
    }
  }

  onEvent(handler: PiEventHandler): void {
    this.eventHandlers.push(handler);
  }

  removeEventHandler(handler: PiEventHandler): void {
    const idx = this.eventHandlers.indexOf(handler);
    if (idx !== -1) {
      this.eventHandlers.splice(idx, 1);
    }
  }

  isAlive(): boolean {
    return this.alive;
  }

  getExitCode(): number | null {
    return this.exitCode;
  }

  kill(): Promise<void> {
    return new Promise<void>((resolve) => {
      if (!this.alive) {
        resolve();
        return;
      }

      const forceKillTimer = setTimeout(() => {
        if (this.alive) {
          this.process.kill("SIGKILL");
        }
      }, 5000);

      this.process.once("exit", () => {
        clearTimeout(forceKillTimer);
        resolve();
      });

      this.process.kill("SIGTERM");
    });
  }
}
