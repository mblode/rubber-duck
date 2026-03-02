import { createConnection, type Socket } from "node:net";
import { createInterface } from "node:readline";
import { SOCKET_PATH } from "./constants.js";
import type {
  DaemonEvent,
  DaemonMessage,
  DaemonRequest,
  DaemonRequestMap,
  DaemonResponse,
} from "./types.js";
import { isDaemonEvent, isDaemonResponse } from "./types.js";
import { generateId } from "./utils.js";

interface PendingRequest {
  reject: (error: Error) => void;
  resolve: (response: DaemonResponse) => void;
  timer: ReturnType<typeof setTimeout>;
}

type DaemonEventHandler = (event: DaemonEvent) => void;

export class DaemonClient {
  private readonly socket: Socket;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly eventHandlers: DaemonEventHandler[] = [];
  private connected = false;

  private constructor(socket: Socket) {
    this.socket = socket;
    this.connected = true;

    const rl = createInterface({ input: socket });

    rl.on("line", (line) => {
      if (!line.trim()) {
        return;
      }
      try {
        const msg = JSON.parse(line) as DaemonMessage;
        if (isDaemonResponse(msg)) {
          const pending = this.pending.get(msg.id);
          if (pending) {
            clearTimeout(pending.timer);
            this.pending.delete(msg.id);
            pending.resolve(msg);
          }
        } else if (isDaemonEvent(msg)) {
          for (const handler of this.eventHandlers) {
            try {
              handler(msg);
            } catch {
              // Don't let handler errors crash the client
            }
          }
        }
      } catch {
        // Ignore unparseable lines
      }
    });

    socket.on("close", () => {
      this.connected = false;
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Daemon disconnected"));
        this.pending.delete(id);
      }
    });

    socket.on("error", () => {
      this.connected = false;
    });
  }

  static connect(
    options?: number | { socketPath?: string; timeoutMs?: number }
  ): Promise<DaemonClient> {
    const socketPath =
      typeof options === "object" ? options.socketPath : undefined;
    const timeoutMs =
      typeof options === "number" ? options : (options?.timeoutMs ?? 5000);
    return new Promise<DaemonClient>((resolve, reject) => {
      const socket = createConnection({ path: socketPath ?? SOCKET_PATH });

      const timer = setTimeout(() => {
        socket.destroy();
        reject(new Error("Connection to daemon timed out"));
      }, timeoutMs);

      socket.on("connect", () => {
        clearTimeout(timer);
        resolve(new DaemonClient(socket));
      });

      socket.on("error", (err) => {
        clearTimeout(timer);
        reject(
          new Error(
            `Cannot connect to daemon: ${err.message}. Run \`duck\` to start.`
          )
        );
      });
    });
  }

  request<M extends DaemonRequest["method"]>(
    method: M,
    params: DaemonRequestMap[M],
    timeoutMs = 30_000
  ): Promise<DaemonResponse> {
    if (!this.connected) {
      throw new Error("Not connected to daemon");
    }

    const id = generateId();
    const request = { id, method, params } as DaemonRequest;
    const line = `${JSON.stringify(request)}\n`;

    return new Promise<DaemonResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Request "${method}" timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      if (!this.socket.write(line)) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new Error("Failed to write to daemon socket"));
      }
    });
  }

  onEvent(handler: DaemonEventHandler): void {
    this.eventHandlers.push(handler);
  }

  removeEventHandler(handler: DaemonEventHandler): void {
    const idx = this.eventHandlers.indexOf(handler);
    if (idx !== -1) {
      this.eventHandlers.splice(idx, 1);
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  close(): void {
    this.connected = false;
    this.socket.destroy();
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Client closed"));
      this.pending.delete(id);
    }
  }
}
