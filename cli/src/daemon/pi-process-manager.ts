import type { Session, Workspace } from "../types.js";
import type { EventBus } from "./event-bus.js";
import { PiProcess } from "./pi-process.js";

export class PiProcessManager {
  private readonly processes = new Map<string, PiProcess>();
  private readonly eventBus: EventBus;

  constructor(eventBus: EventBus) {
    this.eventBus = eventBus;
  }

  getOrSpawn(session: Session, workspace: Workspace): PiProcess {
    const existing = this.processes.get(session.id);
    if (existing?.isAlive()) {
      return existing;
    }

    // Clean up dead process if exists
    if (existing) {
      this.processes.delete(session.id);
    }

    const proc = new PiProcess(workspace.path, {
      sessionId: session.id,
      sessionFile: session.piSessionFile || undefined,
      continueSession: !!session.piSessionFile,
    });

    // Wire Pi events to EventBus
    proc.onEvent((event) => {
      this.eventBus.publish(session.id, event);
    });

    this.processes.set(session.id, proc);
    return proc;
  }

  get(sessionId: string): PiProcess | undefined {
    return this.processes.get(sessionId);
  }

  isRunning(sessionId: string): boolean {
    const proc = this.processes.get(sessionId);
    return proc?.isAlive() ?? false;
  }

  remove(sessionId: string): void {
    this.processes.delete(sessionId);
  }

  async kill(sessionId: string): Promise<void> {
    const proc = this.processes.get(sessionId);
    if (proc) {
      await proc.kill();
      this.processes.delete(sessionId);
    }
  }

  async killAll(): Promise<void> {
    const kills = [...this.processes.values()].map((p) => p.kill());
    await Promise.allSettled(kills);
    this.processes.clear();
  }

  getRunningSessionIds(): string[] {
    return [...this.processes.entries()]
      .filter(([, proc]) => proc.isAlive())
      .map(([id]) => id);
  }
}
