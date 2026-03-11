import { existsSync, unlinkSync } from "node:fs";
import {
  createConnection,
  createServer,
  type Server,
  type Socket,
} from "node:net";
import { createInterface } from "node:readline";
import { SOCKET_PATH } from "../constants.js";
import type { DaemonEvent, DaemonRequest, DaemonResponse } from "../types.js";
import type { ClientRegistry } from "./client-registry.js";

type RequestHandler = (
  clientId: string,
  request: DaemonRequest
) => Promise<DaemonResponse>;

type DisconnectHandler = (clientId: string) => void;

export class SocketServer {
  private readonly server: Server;
  private readonly clientRegistry: ClientRegistry;
  private readonly sockets = new Map<string, Socket>();
  private requestHandler: RequestHandler | null = null;
  private disconnectHandler: DisconnectHandler | null = null;

  constructor(clientRegistry: ClientRegistry) {
    this.clientRegistry = clientRegistry;
    this.server = createServer((socket) => this.handleConnection(socket));
  }

  setRequestHandler(handler: RequestHandler): void {
    this.requestHandler = handler;
  }

  setDisconnectHandler(handler: DisconnectHandler): void {
    this.disconnectHandler = handler;
  }

  private isSocketReachable(): Promise<boolean> {
    return new Promise((resolve) => {
      const socket = createConnection({ path: SOCKET_PATH });
      const timeout = setTimeout(() => {
        socket.destroy();
        resolve(false);
      }, 300);

      socket.on("connect", () => {
        clearTimeout(timeout);
        socket.destroy();
        resolve(true);
      });

      socket.on("error", () => {
        clearTimeout(timeout);
        resolve(false);
      });
    });
  }

  private async prepareSocketPath(): Promise<void> {
    if (!existsSync(SOCKET_PATH)) {
      return;
    }

    if (await this.isSocketReachable()) {
      throw new Error(`Daemon socket already in use: ${SOCKET_PATH}`);
    }

    unlinkSync(SOCKET_PATH);
  }

  async start(): Promise<void> {
    await this.prepareSocketPath();

    return new Promise<void>((resolve, reject) => {
      this.server.on("error", reject);
      this.server.listen(SOCKET_PATH, () => {
        this.server.removeListener("error", reject);
        resolve();
      });
    });
  }

  private handleConnection(socket: Socket): void {
    const clientId = this.clientRegistry.registerClient({
      transport: "socket",
      send: (message) => {
        if (!socket.destroyed) {
          socket.write(`${JSON.stringify(message)}\n`);
        }
      },
      close: () => {
        if (!socket.destroyed) {
          socket.destroy();
        }
      },
    });
    this.sockets.set(clientId, socket);

    const rl = createInterface({ input: socket });
    let closed = false;

    const cleanup = () => {
      if (closed) {
        return;
      }
      closed = true;
      this.sockets.delete(clientId);
      this.clientRegistry.unregisterClient(clientId);
      rl.close();
      this.disconnectHandler?.(clientId);
    };

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
      cleanup();
    });

    socket.on("error", () => {
      cleanup();
    });
  }

  sendToClient(clientId: string, message: DaemonResponse | DaemonEvent): void {
    this.clientRegistry.sendToClient(clientId, message);
  }

  getClientCount(): number {
    return this.clientRegistry.getClientCount();
  }

  stop(): Promise<void> {
    // Close all client connections
    for (const [id, socket] of this.sockets) {
      socket.destroy();
      this.sockets.delete(id);
      this.clientRegistry.unregisterClient(id);
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
