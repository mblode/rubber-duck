import { HEALTH_CHECK_INTERVAL_MS } from "../constants.js";
import type { EventBus } from "./event-bus.js";
import type { MetadataStore } from "./metadata-store.js";
import type { PiProcessManager } from "./pi-process-manager.js";

export class HealthMonitor {
  private readonly processManager: PiProcessManager;
  private readonly eventBus: EventBus;
  private readonly metadataStore: MetadataStore;
  private intervalId: ReturnType<typeof setInterval> | null = null;

  constructor(
    processManager: PiProcessManager,
    eventBus: EventBus,
    metadataStore: MetadataStore
  ) {
    this.processManager = processManager;
    this.eventBus = eventBus;
    this.metadataStore = metadataStore;
  }

  start(): void {
    if (this.intervalId) {
      return;
    }
    this.intervalId = setInterval(() => this.check(), HEALTH_CHECK_INTERVAL_MS);
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  private check(): void {
    const sessions = this.metadataStore.getAllSessions();
    for (const session of sessions) {
      const proc = this.processManager.get(session.id);
      if (proc && !proc.isAlive()) {
        // Process died unexpectedly
        this.processManager.remove(session.id);
        // Notify subscribers
        this.eventBus.publish(session.id, {
          type: "extension_error",
          extensionPath: "daemon",
          event: "process_death",
          error: `Pi process for session "${session.name}" died unexpectedly (exit code: ${proc.getExitCode()})`,
        });
      }
    }
  }
}
