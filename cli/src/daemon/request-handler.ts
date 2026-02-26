import { execSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import {
  CONFIG_PATH,
  LOG_PATH,
  PI_BINARY,
  PI_BINARY_OVERRIDE_ENV,
  SOCKET_PATH,
} from "../constants.js";
import type {
  DaemonRequest,
  DaemonResponse,
  DoctorCheck,
  PiEvent,
  Session,
} from "../types.js";
import { findGitRoot, resolveWorkspacePath } from "../utils.js";
import type { EventBus } from "./event-bus.js";
import type { MetadataStore } from "./metadata-store.js";
import type { PiProcessManager } from "./pi-process-manager.js";
import type { SocketServer } from "./socket-server.js";

const startedAt = Date.now();

export class RequestHandler {
  private readonly metadataStore: MetadataStore;
  private readonly processManager: PiProcessManager;
  private readonly eventBus: EventBus;
  private readonly socketServer: SocketServer;

  constructor(
    metadataStore: MetadataStore,
    processManager: PiProcessManager,
    eventBus: EventBus,
    socketServer: SocketServer
  ) {
    this.metadataStore = metadataStore;
    this.processManager = processManager;
    this.eventBus = eventBus;
    this.socketServer = socketServer;
  }

  private resolveSessionRef(
    sessionRef: string | undefined
  ): Session | undefined {
    return sessionRef
      ? this.metadataStore.resolveSession(sessionRef)
      : this.metadataStore.getActiveVoiceSession();
  }

  private resolveSessions(
    all: boolean | undefined,
    workspaceRef: string | undefined
  ): Session[] {
    if (all) {
      return this.metadataStore.getAllSessions();
    }
    if (workspaceRef) {
      return this.metadataStore.getSessionsForWorkspace(workspaceRef);
    }
    const activeSession = this.metadataStore.getActiveVoiceSession();
    if (activeSession) {
      return this.metadataStore.getSessionsForWorkspace(
        activeSession.workspaceId
      );
    }
    return this.metadataStore.getAllSessions();
  }

  async handle(
    clientId: string,
    request: DaemonRequest
  ): Promise<DaemonResponse> {
    try {
      switch (request.method) {
        case "ping":
          return this.ping(request);
        case "attach":
          return await this.attach(request);
        case "follow":
          return await this.follow(clientId, request);
        case "unfollow":
          return this.unfollow(clientId, request);
        case "extension_ui_response":
          return this.extensionUiResponse(request);
        case "say":
          return await this.say(request);
        case "sessions":
          return this.sessions(request);
        case "use":
          return this.use(request);
        case "new":
          return await this.newSession(request);
        case "abort":
          return await this.abort(request);
        case "doctor":
          return this.doctor(request);
        case "export":
          return await this.exportSession(request);
        case "get_state":
          return await this.getState(request);
        default:
          return {
            id: request.id,
            ok: false,
            error: `Unknown method: ${request.method}`,
          };
      }
    } catch (err) {
      return {
        id: request.id,
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      };
    }
  }

  private ping(request: DaemonRequest): DaemonResponse {
    return {
      id: request.id,
      ok: true,
      data: {
        version: "0.0.1",
        uptime: Date.now() - startedAt,
        clients: this.socketServer.getClientCount(),
      },
    };
  }

  private async attach(request: DaemonRequest): Promise<DaemonResponse> {
    const rawPath = request.params.path as string | undefined;
    const absPath = resolveWorkspacePath(rawPath);

    // Verify directory exists
    if (!(existsSync(absPath) && statSync(absPath).isDirectory())) {
      return {
        id: request.id,
        ok: false,
        error: `Not a directory: ${absPath}`,
      };
    }

    // Find git root or use provided path
    const workspacePath = findGitRoot(absPath) ?? absPath;

    // Get or create workspace
    const workspace = this.metadataStore.addWorkspace(workspacePath);

    // Get or create default session
    const sessions = this.metadataStore.getSessionsForWorkspace(workspace.id);
    let session = sessions[0];
    if (!session) {
      session = this.metadataStore.addSession(workspace.id);
    }

    // Spawn Pi process
    const proc = this.processManager.getOrSpawn(session, workspace);

    // Try to get Pi state to populate session file
    try {
      const stateResp = await proc.sendCommand("get_state");
      if (stateResp.success && stateResp.data) {
        const piSessionFile = stateResp.data.sessionFile as string;
        const piSessionName = stateResp.data.sessionName as string;
        if (piSessionFile) {
          this.metadataStore.updateSession(session.id, { piSessionFile });
        }
        if (piSessionName && session.name.startsWith("duck-")) {
          this.metadataStore.updateSession(session.id, { name: piSessionName });
          const updated = this.metadataStore.getSession(session.id);
          if (updated) {
            session = updated;
          }
        }
      }
    } catch {
      // Pi might not be ready yet, that's fine
    }

    // Set as active voice session
    this.metadataStore.setActiveVoiceSession(session.id);
    this.metadataStore.updateWorkspace(workspace.id, {
      lastActiveSessionId: session.id,
    });

    return {
      id: request.id,
      ok: true,
      data: {
        workspace: { id: workspace.id, path: workspace.path },
        session: { id: session.id, name: session.name },
      },
    };
  }

  private async follow(
    clientId: string,
    request: DaemonRequest
  ): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId as string | undefined;

    let sessionId: string;
    if (sessionRef) {
      const session = this.metadataStore.resolveSession(sessionRef);
      if (!session) {
        return {
          id: request.id,
          ok: false,
          error: `Session not found: ${sessionRef}`,
        };
      }
      sessionId = session.id;
    } else {
      const active = this.metadataStore.getActiveVoiceSession();
      if (!active) {
        return {
          id: request.id,
          ok: false,
          error: "No active session. Run `duck attach` first.",
        };
      }
      sessionId = active.id;
    }

    // Subscribe client to events for this session
    this.eventBus.subscribe(clientId, sessionId, (sid, event) => {
      this.socketServer.sendToClient(clientId, {
        event: event.type,
        sessionId: sid,
        data: event,
      });
    });

    const session = this.metadataStore.getSession(sessionId);
    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: `Session not found: ${sessionId}`,
      };
    }
    const workspace = this.metadataStore.getWorkspace(session.workspaceId);
    const proc = this.processManager.get(sessionId);
    const isRunning = proc?.isAlive() ?? false;
    let sessionState: unknown = null;

    if (isRunning && proc) {
      try {
        const stateResp = await proc.sendCommand("get_state");
        if (stateResp.success && stateResp.data) {
          sessionState = stateResp.data;
        }
      } catch {
        // Session state is best-effort for follow initialization.
      }
    }

    return {
      id: request.id,
      ok: true,
      data: {
        sessionId: session.id,
        sessionName: session.name,
        workspacePath: workspace?.path ?? "unknown",
        isRunning,
        sessionState,
      },
    };
  }

  private unfollow(clientId: string, request: DaemonRequest): DaemonResponse {
    this.eventBus.unsubscribe(clientId);
    return { id: request.id, ok: true };
  }

  private extensionUiResponse(request: DaemonRequest): DaemonResponse {
    const sessionRef = request.params.sessionId as string | undefined;
    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: "No active session for UI response",
      };
    }

    const responsePayload: Record<string, unknown> = {
      id: request.params.id as string,
      value: request.params.value,
      confirmed: request.params.confirmed as boolean | undefined,
      cancelled: request.params.cancelled as boolean | undefined,
    };

    if (!responsePayload.id) {
      return {
        id: request.id,
        ok: false,
        error: "UI response is missing request id",
      };
    }

    const proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      return {
        id: request.id,
        ok: false,
        error: `Pi process for session "${session.name}" is not running`,
      };
    }

    proc.sendUntracked("extension_ui_response", responsePayload);

    return { id: request.id, ok: true, data: { sessionId: session.id } };
  }

  private async say(request: DaemonRequest): Promise<DaemonResponse> {
    const message = request.params.message as string;
    const sessionRef = request.params.sessionId as string | undefined;

    if (!message) {
      return { id: request.id, ok: false, error: "Message is required" };
    }

    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: "No active session. Run `duck attach` first.",
      };
    }

    const proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      return {
        id: request.id,
        ok: false,
        error: `Pi process for session "${session.name}" is not running`,
      };
    }

    // Publish user utterance event for CLI rendering
    this.eventBus.publish(session.id, {
      type: "message_start",
      message: {
        role: "user",
        content: message,
        timestamp: new Date().toISOString(),
      },
    } as PiEvent);

    // Send prompt to Pi
    const response = await proc.sendCommand("prompt", { message });

    this.metadataStore.updateSession(session.id, {
      lastActiveAt: new Date().toISOString(),
    });

    return {
      id: request.id,
      ok: response.success,
      error: response.error,
      data: { sessionId: session.id, sessionName: session.name },
    };
  }

  private sessions(request: DaemonRequest): DaemonResponse {
    const all = request.params.all as boolean | undefined;
    const workspaceRef = request.params.workspaceId as string | undefined;

    const sessions = this.resolveSessions(all, workspaceRef);

    const activeId = this.metadataStore.getActiveVoiceSessionId();

    const sessionData = sessions.map((s) => {
      const workspace = this.metadataStore.getWorkspace(s.workspaceId);
      return {
        id: s.id,
        name: s.name,
        workspacePath: workspace?.path ?? "unknown",
        isActive: s.id === activeId,
        isRunning: this.processManager.isRunning(s.id),
        lastActiveAt: s.lastActiveAt,
      };
    });

    return { id: request.id, ok: true, data: { sessions: sessionData } };
  }

  private use(request: DaemonRequest): DaemonResponse {
    const sessionRef = request.params.sessionId as string;
    if (!sessionRef) {
      return {
        id: request.id,
        ok: false,
        error: "Session name or ID is required",
      };
    }

    const session = this.metadataStore.resolveSession(sessionRef);
    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: `Session not found: ${sessionRef}`,
      };
    }

    this.metadataStore.setActiveVoiceSession(session.id);
    const workspace = this.metadataStore.getWorkspace(session.workspaceId);

    return {
      id: request.id,
      ok: true,
      data: {
        sessionId: session.id,
        sessionName: session.name,
        workspacePath: workspace?.path ?? "unknown",
      },
    };
  }

  private async newSession(request: DaemonRequest): Promise<DaemonResponse> {
    const name = request.params.name as string | undefined;
    const workspaceRef = request.params.workspaceId as string | undefined;

    // Determine workspace
    let workspaceId: string;
    if (workspaceRef) {
      workspaceId = workspaceRef;
    } else {
      const active = this.metadataStore.getActiveVoiceSession();
      if (!active) {
        return {
          id: request.id,
          ok: false,
          error: "No active workspace. Run `duck attach` first.",
        };
      }
      workspaceId = active.workspaceId;
    }

    const workspace = this.metadataStore.getWorkspace(workspaceId);
    if (!workspace) {
      return {
        id: request.id,
        ok: false,
        error: `Workspace not found: ${workspaceId}`,
      };
    }

    // Create session
    const session = this.metadataStore.addSession(workspaceId, name);

    // Spawn Pi process with new session
    const proc = this.processManager.getOrSpawn(session, workspace);

    // Tell Pi to start a new session
    try {
      const resp = await proc.sendCommand("new_session");
      if (resp.success && resp.data) {
        const piSessionFile = resp.data.sessionFile as string;
        if (piSessionFile) {
          this.metadataStore.updateSession(session.id, { piSessionFile });
        }
      }
    } catch {
      // New session in Pi may fail; the process still created a session
    }

    // Set as active
    this.metadataStore.setActiveVoiceSession(session.id);

    return {
      id: request.id,
      ok: true,
      data: { sessionId: session.id, sessionName: session.name },
    };
  }

  private async abort(request: DaemonRequest): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId as string | undefined;

    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return { id: request.id, ok: false, error: "No active session to abort" };
    }

    const proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      return {
        id: request.id,
        ok: false,
        error: "No running operation to abort",
      };
    }

    // Send abort and abort_bash
    await Promise.allSettled([
      proc.sendCommand("abort"),
      proc.sendCommand("abort_bash"),
    ]);

    return {
      id: request.id,
      ok: true,
      data: { sessionId: session.id, sessionName: session.name },
    };
  }

  private doctor(request: DaemonRequest): DaemonResponse {
    const checks: DoctorCheck[] = [];

    // Check daemon (it's running since we're responding)
    checks.push({
      name: "daemon",
      status: "ok",
      message: `Running (pid ${process.pid}, uptime ${Math.floor((Date.now() - startedAt) / 1000)}s)`,
    });

    // Check Pi binary
    try {
      const version = execSync(`${PI_BINARY} --version 2>/dev/null`, {
        encoding: "utf-8",
      }).trim();
      checks.push({
        name: "pi",
        status: "ok",
        message: `${PI_BINARY} ${version}`,
      });
    } catch {
      checks.push({
        name: "pi",
        status: "fail",
        message: `Pi not found. Install in cli: npm install @mariozechner/pi-coding-agent, install globally: npm install -g @mariozechner/pi-coding-agent, or set ${PI_BINARY_OVERRIDE_ENV}.`,
      });
    }

    // Check socket
    if (existsSync(SOCKET_PATH)) {
      checks.push({ name: "socket", status: "ok", message: SOCKET_PATH });
    } else {
      checks.push({
        name: "socket",
        status: "fail",
        message: "Socket file missing",
      });
    }

    checks.push({
      name: "config",
      status: existsSync(CONFIG_PATH) ? "ok" : "warn",
      message: existsSync(CONFIG_PATH)
        ? CONFIG_PATH
        : "Config file missing, will be created on restart",
    });

    checks.push({
      name: "log",
      status: existsSync(LOG_PATH) ? "ok" : "warn",
      message: existsSync(LOG_PATH) ? LOG_PATH : "Log file not created yet",
    });

    // Check providers
    const providerVars = [
      "ANTHROPIC_API_KEY",
      "OPENAI_API_KEY",
      "GOOGLE_API_KEY",
      "MISTRAL_API_KEY",
    ];
    const foundProviders = providerVars.filter((v) => process.env[v]);
    if (foundProviders.length > 0) {
      checks.push({
        name: "providers",
        status: "ok",
        message: foundProviders
          .map((v) => v.replace("_API_KEY", "").toLowerCase())
          .join(", "),
      });
    } else {
      checks.push({
        name: "providers",
        status: "warn",
        message: "No API keys found. Set ANTHROPIC_API_KEY or use `pi /login`",
      });
    }

    // Check active sessions
    const runningSessions = this.processManager.getRunningSessionIds();
    checks.push({
      name: "sessions",
      status: "ok",
      message: `${runningSessions.length} running`,
    });

    return { id: request.id, ok: true, data: { checks } };
  }

  private async exportSession(request: DaemonRequest): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId as string | undefined;
    const outPath = request.params.outPath as string | undefined;

    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return { id: request.id, ok: false, error: "No session to export" };
    }
    const workspace = this.metadataStore.getWorkspace(session.workspaceId);

    const proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      return {
        id: request.id,
        ok: false,
        error: "Pi process not running for this session",
      };
    }

    const response = await proc.sendCommand("export_html");
    if (!response.success) {
      return {
        id: request.id,
        ok: false,
        error: response.error ?? "Export failed",
      };
    }

    return {
      id: request.id,
      ok: true,
      data: {
        sessionId: session.id,
        sessionName: session.name,
        workspacePath: workspace?.path,
        exportData: response.data,
        outPath: outPath ?? `session-${session.name}.html`,
      },
    };
  }

  private async getState(request: DaemonRequest): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId as string | undefined;

    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return { id: request.id, ok: false, error: "No active session" };
    }

    const proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      return {
        id: request.id,
        ok: true,
        data: {
          sessionId: session.id,
          sessionName: session.name,
          isRunning: false,
        },
      };
    }

    const response = await proc.sendCommand("get_state");
    return {
      id: request.id,
      ok: response.success,
      error: response.error,
      data: {
        sessionId: session.id,
        sessionName: session.name,
        isRunning: true,
        piState: response.data,
      },
    };
  }
}
