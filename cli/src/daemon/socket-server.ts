import { existsSync, unlinkSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { createInterface } from "node:readline";
import { SOCKET_PATH } from "../constants.js";
import type { DaemonEvent, DaemonRequest, DaemonResponse } from "../types.js";
import { generateId } from "../utils.js";

type RequestHandler = (
  clientId: string,
  request: DaemonRequest
) => Promise<DaemonResponse>;

export class SocketServer {
  private readonly server: Server;
  private readonly clients = new Map<string, Socket>();
  private requestHandler: RequestHandler | null = null;

  constructor() {
    this.server = createServer((socket) => this.handleConnection(socket));
  }

  setRequestHandler(handler: RequestHandler): void {
    this.requestHandler = handler;
  }

  start(): Promise<void> {
    // Remove stale socket file
    if (existsSync(SOCKET_PATH)) {
      try {
        unlinkSync(SOCKET_PATH);
      } catch {
        /* ignore */
      }
    }

    return new Promise<void>((resolve, reject) => {
      this.server.on("error", reject);
      this.server.listen(SOCKET_PATH, () => {
        this.server.removeListener("error", reject);
        resolve();
      });
    });
  }

  private handleConnection(socket: Socket): void {
    const clientId = generateId();
    this.clients.set(clientId, socket);

    const rl = createInterface({ input: socket });

    rl.on("line", async (line) => {
      if (!line.trim()) {
        return;
      }
      try {
        const request = JSON.parse(line) as DaemonRequest;
        if (this.requestHandler) {
          const response = await this.requestHandler(clientId, request);
          this.sendToClient(clientId, response);
        }
      } catch (err) {
        // Send error response for parse failures
        const errorResponse: DaemonResponse = {
          id: "unknown",
          ok: false,
          error: `Failed to parse request: ${err instanceof Error ? err.message : String(err)}`,
        };
        this.sendToClient(clientId, errorResponse);
      }
    });

    socket.on("close", () => {
      this.clients.delete(clientId);
      rl.close();
      // Notify that client disconnected (the request handler can clean up subscriptions)
      if (this.requestHandler) {
        this.requestHandler(clientId, {
          id: generateId(),
          method: "unfollow",
          params: {},
        }).catch(() => {
          // Best-effort cleanup on disconnect
        });
      }
    });

    socket.on("error", () => {
      this.clients.delete(clientId);
      rl.close();
    });
  }

  sendToClient(clientId: string, message: DaemonResponse | DaemonEvent): void {
    const socket = this.clients.get(clientId);
    if (!socket || socket.destroyed) {
      return;
    }
    try {
      socket.write(`${JSON.stringify(message)}\n`);
    } catch {
      // Client disconnected
      this.clients.delete(clientId);
    }
  }

  getClientCount(): number {
    return this.clients.size;
  }

  stop(): Promise<void> {
    // Close all client connections
    for (const [id, socket] of this.clients) {
      socket.destroy();
      this.clients.delete(id);
    }

    return new Promise<void>((resolve) => {
      this.server.close(() => {
        // Clean up socket file
        if (existsSync(SOCKET_PATH)) {
          try {
            unlinkSync(SOCKET_PATH);
          } catch {
            /* ignore */
          }
        }
        resolve();
      });
    });
  }
}
