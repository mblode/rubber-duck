import type { PiEvent } from "../types.js";

type EventHandler = (sessionId: string, event: PiEvent) => void;

export class EventBus {
  // sessionId -> Set of clientIds
  private readonly subscriptions = new Map<string, Set<string>>();
  // clientId -> handler function
  private readonly handlers = new Map<string, EventHandler>();

  subscribe(clientId: string, sessionId: string, handler: EventHandler): void {
    if (!this.subscriptions.has(sessionId)) {
      this.subscriptions.set(sessionId, new Set());
    }
    const clients = this.subscriptions.get(sessionId);
    clients?.add(clientId);
    this.handlers.set(clientId, handler);
  }

  unsubscribe(clientId: string): void {
    this.handlers.delete(clientId);
    for (const [sessionId, clients] of this.subscriptions) {
      clients.delete(clientId);
      if (clients.size === 0) {
        this.subscriptions.delete(sessionId);
      }
    }
  }

  publish(sessionId: string, event: PiEvent): void {
    const clients = this.subscriptions.get(sessionId);
    if (!clients) {
      return;
    }
    for (const clientId of clients) {
      const handler = this.handlers.get(clientId);
      if (handler) {
        try {
          handler(sessionId, event);
        } catch {
          // Don't let one client's error affect others
        }
      }
    }
  }

  getSubscriberCount(sessionId: string): number {
    return this.subscriptions.get(sessionId)?.size ?? 0;
  }

  clear(): void {
    this.subscriptions.clear();
    this.handlers.clear();
  }
}
