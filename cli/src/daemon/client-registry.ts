import type { DaemonEvent, DaemonResponse } from "../types.js";
import { generateId } from "../utils.js";

export type ClientTransport = "socket" | "remote_ws";

interface ClientRegistration {
  close: () => void;
  id?: string;
  send: (message: DaemonResponse | DaemonEvent) => void;
  transport: ClientTransport;
}

interface ClientRecord {
  close: () => void;
  id: string;
  send: (message: DaemonResponse | DaemonEvent) => void;
  transport: ClientTransport;
}

export class ClientRegistry {
  private readonly clients = new Map<string, ClientRecord>();

  registerClient(registration: ClientRegistration): string {
    const id = registration.id?.trim() || generateId();
    if (this.clients.has(id)) {
      throw new Error(`Client already registered: ${id}`);
    }

    this.clients.set(id, {
      id,
      transport: registration.transport,
      send: registration.send,
      close: registration.close,
    });

    return id;
  }

  unregisterClient(clientId: string): void {
    this.clients.delete(clientId);
  }

  hasClient(clientId: string): boolean {
    return this.clients.has(clientId);
  }

  getClientTransport(clientId: string): ClientTransport | null {
    return this.clients.get(clientId)?.transport ?? null;
  }

  sendToClient(
    clientId: string,
    message: DaemonResponse | DaemonEvent
  ): boolean {
    const client = this.clients.get(clientId);
    if (!client) {
      return false;
    }

    try {
      client.send(message);
      return true;
    } catch {
      this.clients.delete(clientId);
      return false;
    }
  }

  getClientCount(): number {
    return this.clients.size;
  }

  closeAll(): void {
    for (const [clientId, client] of this.clients) {
      try {
        client.close();
      } catch {
        // Best-effort shutdown only.
      }
      this.clients.delete(clientId);
    }
  }
}
