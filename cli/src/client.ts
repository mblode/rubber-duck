import { createConnection, type Socket } from "node:net";
import { createInterface } from "node:readline";
import { WebSocket } from "ws";
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

interface ClientTransport {
  close(): void;
  onClose(handler: () => void): void;
  onError(handler: (error: Error) => void): void;
  onLine(handler: (line: string) => void): void;
  send(line: string): boolean;
}

interface DaemonClientConnectOptions {
  authToken?: string;
  remoteUrl?: string;
  socketPath?: string;
  timeoutMs?: number;
}

function rawDataToString(raw: import("ws").RawData): string {
  if (typeof raw === "string") {
    return raw;
  }
  if (Buffer.isBuffer(raw)) {
    return raw.toString("utf8");
  }
  if (Array.isArray(raw)) {
    return Buffer.concat(
      raw.map((value) => (Buffer.isBuffer(value) ? value : Buffer.from(value)))
    ).toString("utf8");
  }
  return Buffer.from(raw).toString("utf8");
}

function buildRemoteWebSocketUrl(remoteUrl: string): string {
  const url = new URL(remoteUrl);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws";
  url.search = "";
  return url.toString();
}

export class DaemonClient {
  private readonly transport: ClientTransport;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly eventHandlers: DaemonEventHandler[] = [];
  private connected = false;

  private constructor(transport: ClientTransport) {
    this.transport = transport;
    this.connected = true;

    this.transport.onLine((line) => {
      if (!line.trim()) {
        return;
      }

      try {
        const message = JSON.parse(line) as DaemonMessage;
        if (isDaemonResponse(message)) {
          const pending = this.pending.get(message.id);
          if (!pending) {
            return;
          }

          clearTimeout(pending.timer);
          this.pending.delete(message.id);
          pending.resolve(message);
          return;
        }

        if (isDaemonEvent(message)) {
          for (const handler of this.eventHandlers) {
            try {
              handler(message);
            } catch {
              // Handler failures should not crash the client transport.
            }
          }
        }
      } catch {
        // Ignore malformed lines from the daemon transport.
      }
    });

    this.transport.onClose(() => {
      this.connected = false;
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Daemon disconnected"));
        this.pending.delete(id);
      }
    });

    this.transport.onError(() => {
      this.connected = false;
    });
  }

  private static createSocketTransport(socket: Socket): ClientTransport {
    const rl = createInterface({ input: socket });

    return {
      send: (line) => socket.write(line),
      close: () => {
        rl.close();
        socket.destroy();
      },
      onLine: (handler) => {
        rl.on("line", handler);
      },
      onClose: (handler) => {
        socket.on("close", handler);
      },
      onError: (handler) => {
        socket.on("error", (error) => handler(error));
      },
    };
  }

  private static createWebSocketTransport(socket: WebSocket): ClientTransport {
    return {
      send: (line) => {
        if (socket.readyState !== WebSocket.OPEN) {
          return false;
        }
        socket.send(line);
        return true;
      },
      close: () => {
        socket.close();
      },
      onLine: (handler) => {
        socket.on("message", (raw) => {
          handler(rawDataToString(raw));
        });
      },
      onClose: (handler) => {
        socket.on("close", handler);
      },
      onError: (handler) => {
        socket.on("error", (error) =>
          handler(error instanceof Error ? error : new Error(String(error)))
        );
      },
    };
  }

  static connect(
    options?: number | DaemonClientConnectOptions
  ): Promise<DaemonClient> {
    if (typeof options === "object" && options.remoteUrl) {
      return DaemonClient.connectRemote(options);
    }

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
        resolve(new DaemonClient(DaemonClient.createSocketTransport(socket)));
      });

      socket.on("error", (error) => {
        clearTimeout(timer);
        reject(
          new Error(
            `Cannot connect to daemon: ${error.message}. Run \`duck\` to start.`
          )
        );
      });
    });
  }

  private static connectRemote(
    options: DaemonClientConnectOptions
  ): Promise<DaemonClient> {
    const timeoutMs = options.timeoutMs ?? 5000;
    const wsUrl = buildRemoteWebSocketUrl(options.remoteUrl ?? "");

    return new Promise<DaemonClient>((resolve, reject) => {
      const socket = new WebSocket(wsUrl, {
        headers: options.authToken
          ? {
              Authorization: `Bearer ${options.authToken}`,
            }
          : undefined,
      });

      const timer = setTimeout(() => {
        socket.close();
        reject(new Error("Connection to remote daemon timed out"));
      }, timeoutMs);

      socket.on("open", () => {
        clearTimeout(timer);
        resolve(
          new DaemonClient(DaemonClient.createWebSocketTransport(socket))
        );
      });

      socket.on("error", (error) => {
        clearTimeout(timer);
        reject(
          new Error(
            `Cannot connect to remote daemon: ${error.message}. Check the remote URL and auth token.`
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

      if (!this.transport.send(line)) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new Error("Failed to write to daemon transport"));
      }
    });
  }

  onEvent(handler: DaemonEventHandler): void {
    this.eventHandlers.push(handler);
  }

  removeEventHandler(handler: DaemonEventHandler): void {
    const index = this.eventHandlers.indexOf(handler);
    if (index !== -1) {
      this.eventHandlers.splice(index, 1);
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  close(): void {
    this.connected = false;
    this.transport.close();

    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Client closed"));
      this.pending.delete(id);
    }
  }
}
