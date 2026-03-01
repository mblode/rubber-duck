import { type ChildProcess, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import {
  PI_BINARY,
  PI_COMMAND_TIMEOUT_MS,
  PI_DEFAULT_THINKING,
  PI_THINKING_OVERRIDE_ENV,
  PI_TOOLS,
  resolveDefaultPiModel,
  resolveDefaultPiProvider,
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

type PiEventHandler = (event: PiEvent) => void;

export class PiProcess {
  private readonly process: ChildProcess;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly completedPromptAcks = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
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
      "--tools",
      PI_TOOLS.join(","),
    ];
    // Pi CLI does not expose sandbox/approval flags. We explicitly enable the
    // full built-in tool set so the agent has full codebase inspection access.
    const piModel = resolveDefaultPiModel();
    if (piModel) {
      args.push("--model", piModel);
    }
    const piProvider = resolveDefaultPiProvider();
    if (piProvider) {
      args.push("--provider", piProvider);
    }
    const piThinking =
      process.env[PI_THINKING_OVERRIDE_ENV]?.trim() ?? PI_DEFAULT_THINKING;
    args.push("--thinking", piThinking);

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
      this.clearCompletedPromptAcks();
      // Reject all pending requests
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`Pi process exited with code ${code}`));
        this.pending.delete(id);
      }
    });

    this.process.on("error", (err) => {
      this.alive = false;
      this.clearCompletedPromptAcks();
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
        if (pending.command === "prompt" && response.success) {
          const cleanupTimer = setTimeout(() => {
            this.completedPromptAcks.delete(response.id as string);
          }, PI_COMMAND_TIMEOUT_MS);
          this.completedPromptAcks.set(response.id, cleanupTimer);
        }
        pending.resolve(response);
        return;
      }

      if (
        response.command === "prompt" &&
        response.success === false &&
        this.completedPromptAcks.has(response.id)
      ) {
        const cleanupTimer = this.completedPromptAcks.get(response.id);
        if (cleanupTimer) {
          clearTimeout(cleanupTimer);
        }
        this.completedPromptAcks.delete(response.id);
        this.emitEvent({
          type: "prompt_error",
          error: response.error ?? "Prompt failed",
        });
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
        this.clearCompletedPromptAcks();
        resolve();
        return;
      }

      const forceKillTimer = setTimeout(() => {
        if (this.alive) {
          this.process.kill("SIGKILL");
        }
      }, 5000);

      this.process.once("exit", () => {
        this.clearCompletedPromptAcks();
        clearTimeout(forceKillTimer);
        resolve();
      });

      this.process.kill("SIGTERM");
    });
  }

  private emitEvent(event: PiEvent): void {
    for (const handler of this.eventHandlers) {
      try {
        handler(event);
      } catch {
        // Don't let handler errors crash the process
      }
    }
  }

  private clearCompletedPromptAcks(): void {
    for (const timer of this.completedPromptAcks.values()) {
      clearTimeout(timer);
    }
    this.completedPromptAcks.clear();
  }
}
