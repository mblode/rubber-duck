import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { APP_SUPPORT } from "../constants.js";
import { runHealthChecks } from "../health-checks.js";
import type {
  DaemonRequest,
  DaemonRequestMap,
  DaemonResponse,
  PiEvent,
  Session,
  VoiceStateValue,
} from "../types.js";
import { findGitRoot, resolveWorkspacePath } from "../utils.js";
import type { ClientRegistry } from "./client-registry.js";
import type { EventBus } from "./event-bus.js";
import type { MetadataStore } from "./metadata-store.js";
import type { PiProcessManager } from "./pi-process-manager.js";
import type { RemoteControlManager } from "./remote-control.js";
import { executeVoiceTool } from "./voice-tools.js";

interface RequestFor<M extends keyof DaemonRequestMap> {
  id: string;
  method: M;
  params: DaemonRequestMap[M];
}

const startedAt = Date.now();

interface VoiceClientState {
  clientType: "local-app" | "remote-ios" | "remote-web";
  sessionId: string | null;
  state: VoiceStateValue;
}

export class RequestHandler {
  private readonly metadataStore: MetadataStore;
  private readonly processManager: PiProcessManager;
  private readonly eventBus: EventBus;
  private readonly clientRegistry: ClientRegistry;
  private readonly remoteControlManager: RemoteControlManager;
  private readonly voiceClients = new Map<string, VoiceClientState>();

  constructor(
    metadataStore: MetadataStore,
    processManager: PiProcessManager,
    eventBus: EventBus,
    clientRegistry: ClientRegistry,
    remoteControlManager: RemoteControlManager
  ) {
    this.metadataStore = metadataStore;
    this.processManager = processManager;
    this.eventBus = eventBus;
    this.clientRegistry = clientRegistry;
    this.remoteControlManager = remoteControlManager;
  }

  handleDisconnect(clientId: string): void {
    this.cleanupClientState(clientId);
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

  private getVoiceOwner(
    sessionId: string
  ): { clientId: string; voiceState: VoiceClientState } | null {
    for (const [clientId, voiceState] of this.voiceClients) {
      if (
        voiceState.sessionId === sessionId &&
        voiceState.state !== "idle" &&
        this.clientRegistry.hasClient(clientId)
      ) {
        return { clientId, voiceState };
      }
    }

    return null;
  }

  private findIdleVoiceClient(
    sessionId: string
  ): { clientId: string; voiceState: VoiceClientState } | null {
    let fallback: { clientId: string; voiceState: VoiceClientState } | null =
      null;
    for (const [clientId, voiceState] of this.voiceClients) {
      if (
        voiceState.state !== "idle" ||
        !this.clientRegistry.hasClient(clientId)
      ) {
        continue;
      }
      // Prefer idle client already bound to this session
      if (voiceState.sessionId === sessionId) {
        return { clientId, voiceState };
      }
      fallback ??= { clientId, voiceState };
    }
    return fallback;
  }

  private notifyVoiceSessionChanged(
    session: Session,
    workspacePath: string
  ): void {
    for (const [clientId, voiceState] of this.voiceClients) {
      const shouldNotify =
        voiceState.state === "idle" ||
        !voiceState.sessionId ||
        voiceState.sessionId === session.id;

      if (!shouldNotify) {
        continue;
      }

      voiceState.sessionId = session.id;
      this.clientRegistry.sendToClient(clientId, {
        event: "voice_session_changed",
        sessionId: session.id,
        data: {
          type: "voice_session_changed" as const,
          sessionId: session.id,
          sessionName: session.name,
          workspacePath,
        },
      });
    }
  }

  private publishVoiceStatus(sessionId: string, state: VoiceStateValue): void {
    this.eventBus.publish(sessionId, {
      type: "extension_ui_request",
      id: `voice-state-${Date.now()}`,
      method: "setStatus",
      message: `voice:${state}`,
    } as PiEvent);
  }

  private isLocalControlClient(clientId: string): boolean {
    return this.clientRegistry.getClientTransport(clientId) === "socket";
  }

  async handle(
    clientId: string,
    request: DaemonRequest
  ): Promise<DaemonResponse> {
    const { id } = request;
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
        case "workspaces":
          return this.workspaces(request);
        case "activate_session":
          return this.activateSession(request);
        case "abort":
          return await this.abort(request);
        case "doctor":
          return this.doctor(request);
        case "get_state":
          return await this.getState(request);
        case "remote_status":
          return this.remoteStatus(clientId, request);
        case "remote_configure":
          return await this.remoteConfigure(clientId, request);
        case "voice_connect":
          return this.voiceConnect(clientId, request);
        case "voice_start":
          return this.voiceStart(clientId, request);
        case "voice_tool_call":
          return await this.voiceToolCall(clientId, request);
        case "voice_state":
          return this.voiceState(clientId, request);
        default: {
          const _exhaustive: never = request;
          return {
            id,
            ok: false,
            error: `Unknown method: ${String((_exhaustive as DaemonRequest).method)}`,
          };
        }
      }
    } catch (err) {
      return {
        id,
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      };
    }
  }

  private ping(request: RequestFor<"ping">): DaemonResponse {
    return {
      id: request.id,
      ok: true,
      data: {
        version: "0.0.1",
        uptime: Date.now() - startedAt,
        clients: this.clientRegistry.getClientCount(),
      },
    };
  }

  private async attach(request: RequestFor<"attach">): Promise<DaemonResponse> {
    const rawPath = request.params.path;
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

    this.notifyVoiceSessionChanged(session, workspace.path);

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
    request: RequestFor<"follow">
  ): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId;

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
          error: "No active session. Run `duck` first.",
        };
      }
      sessionId = active.id;
    }

    if (!this.clientRegistry.hasClient(clientId)) {
      return {
        id: request.id,
        ok: false,
        error: "Streaming client is not connected",
      };
    }

    // Ensure a client only has one active follow subscription at a time.
    this.eventBus.unsubscribe(clientId);

    // Subscribe client to events for this session
    this.eventBus.subscribe(clientId, sessionId, (sid, event) => {
      this.clientRegistry.sendToClient(clientId, {
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
    const appHistoryFile = join(APP_SUPPORT, "sessions", `${session.id}.jsonl`);
    const appHistoryExists = existsSync(appHistoryFile);
    const appHistorySizeBytes = appHistoryExists
      ? (() => {
          try {
            return statSync(appHistoryFile).size;
          } catch {
            return 0;
          }
        })()
      : 0;
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
        appHistoryFile,
        appHistoryExists,
        appHistorySizeBytes,
      },
    };
  }

  private unfollow(
    clientId: string,
    request: RequestFor<"unfollow">
  ): DaemonResponse {
    this.cleanupClientState(clientId);
    return { id: request.id, ok: true };
  }

  private extensionUiResponse(
    request: RequestFor<"extension_ui_response">
  ): DaemonResponse {
    const sessionRef = request.params.sessionId;
    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: "No active session for UI response",
      };
    }

    const responsePayload: Record<string, unknown> = {
      id: request.params.id,
      value: request.params.value,
      confirmed: request.params.confirmed,
      cancelled: request.params.cancelled,
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

  private async say(request: RequestFor<"say">): Promise<DaemonResponse> {
    const message = request.params.message;
    const preferPi = request.params.preferPi ?? false;
    const sessionRef = request.params.sessionId;

    if (!message) {
      return { id: request.id, ok: false, error: "Message is required" };
    }

    const session = this.resolveSessionRef(sessionRef);

    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: "No active session. Run `duck` first.",
      };
    }

    // Route to voice only when the app is connected and actively running a voice session.
    // If the app is connected but idle, route through Pi so `duck say` always works.
    const voiceOwner = preferPi ? null : this.getVoiceOwner(session.id);

    if (voiceOwner) {
      // Voice-routed messages don't emit Pi user message events, so synthesize one
      // for CLI rendering consistency.
      this.eventBus.publish(session.id, {
        type: "message_start",
        message: {
          role: "user",
          content: message,
          timestamp: new Date().toISOString(),
        },
      } as PiEvent);

      if (!this.clientRegistry.hasClient(voiceOwner.clientId)) {
        this.voiceClients.delete(voiceOwner.clientId);
        return {
          id: request.id,
          ok: false,
          error: "Voice client disconnected",
        };
      }

      const sent = this.clientRegistry.sendToClient(voiceOwner.clientId, {
        event: "voice_say",
        sessionId: session.id,
        data: { text: message },
      });
      if (!sent) {
        this.voiceClients.delete(voiceOwner.clientId);
        return {
          id: request.id,
          ok: false,
          error: "Voice client disconnected",
        };
      }
      return {
        id: request.id,
        ok: true,
        data: { sessionId: session.id, sessionName: session.name },
      };
    }

    let proc = this.processManager.get(session.id);
    if (!proc?.isAlive()) {
      const workspace = this.metadataStore.getWorkspace(session.workspaceId);
      if (!workspace) {
        return {
          id: request.id,
          ok: false,
          error: `Workspace for session "${session.name}" was not found`,
        };
      }
      proc = this.processManager.getOrSpawn(session, workspace);
    }

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

  private sessions(request: RequestFor<"sessions">): DaemonResponse {
    const all = request.params.all;
    const workspaceRef = request.params.workspaceId;

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

  private workspaces(request: RequestFor<"workspaces">): DaemonResponse {
    const activeSessionId = this.metadataStore.getActiveVoiceSessionId();
    const workspaces = this.metadataStore
      .getData()
      .workspaces.map((workspace) => {
        const sessions = this.metadataStore.getSessionsForWorkspace(
          workspace.id
        );
        return {
          id: workspace.id,
          path: workspace.path,
          lastActiveSessionId: workspace.lastActiveSessionId,
          sessionCount: sessions.length,
          sessions: sessions.map((session) => ({
            id: session.id,
            name: session.name,
            isActive: session.id === activeSessionId,
            isRunning: this.processManager.isRunning(session.id),
            lastActiveAt: session.lastActiveAt,
          })),
        };
      });

    return { id: request.id, ok: true, data: { workspaces } };
  }

  private activateSession(
    request: RequestFor<"activate_session">
  ): DaemonResponse {
    const session = this.metadataStore.resolveSession(request.params.sessionId);
    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: `Session not found: ${request.params.sessionId}`,
      };
    }

    const workspace = this.metadataStore.getWorkspace(session.workspaceId);
    if (!workspace) {
      return {
        id: request.id,
        ok: false,
        error: `Workspace not found for session: ${session.id}`,
      };
    }

    this.metadataStore.setActiveVoiceSession(session.id);
    this.metadataStore.updateWorkspace(workspace.id, {
      lastActiveSessionId: session.id,
    });

    this.notifyVoiceSessionChanged(session, workspace.path);

    return {
      id: request.id,
      ok: true,
      data: {
        session: {
          id: session.id,
          name: session.name,
          workspaceId: session.workspaceId,
        },
        workspace: {
          id: workspace.id,
          path: workspace.path,
        },
      },
    };
  }

  private async abort(request: RequestFor<"abort">): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId;

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

  private doctor(request: RequestFor<"doctor">): DaemonResponse {
    const checks = runHealthChecks("daemon", {
      pid: process.pid,
      uptimeMs: Date.now() - startedAt,
      runningSessionCount: this.processManager.getRunningSessionIds().length,
    });
    const remoteStatus = this.remoteControlManager.getStatus();
    const remoteCheckStatus =
      remoteStatus.enabled && remoteStatus.listening ? "ok" : "warn";
    let remoteMessage = "Disabled";
    if (remoteStatus.enabled && remoteStatus.listening) {
      remoteMessage = `${String(remoteStatus.httpUrl ?? "remote")} (${String(remoteStatus.connectedClients)} clients)`;
    } else if (remoteStatus.enabled) {
      remoteMessage = "Configured but not listening";
    }
    checks.push({
      name: "remote",
      status: remoteCheckStatus,
      message: remoteMessage,
    });

    return { id: request.id, ok: true, data: { checks } };
  }

  private async getState(
    request: RequestFor<"get_state">
  ): Promise<DaemonResponse> {
    const sessionRef = request.params.sessionId;

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

  private remoteStatus(
    clientId: string,
    request: RequestFor<"remote_status">
  ): DaemonResponse {
    const includeToken =
      request.params.includeToken && this.isLocalControlClient(clientId);

    return {
      id: request.id,
      ok: true,
      data: {
        status: this.remoteControlManager.getStatus(),
        authToken: includeToken
          ? (this.remoteControlManager.getPersistedAuthToken() ?? undefined)
          : undefined,
      },
    };
  }

  private async remoteConfigure(
    clientId: string,
    request: RequestFor<"remote_configure">
  ): Promise<DaemonResponse> {
    if (!this.isLocalControlClient(clientId)) {
      return {
        id: request.id,
        ok: false,
        error: "Remote configuration is only available to local clients",
      };
    }

    const { issuedToken, status } = await this.remoteControlManager.configure({
      enabled: request.params.enabled,
      host: request.params.host,
      port: request.params.port,
      rotateToken: request.params.rotateToken,
      tlsCertPath: request.params.tlsCertPath,
      tlsKeyPath: request.params.tlsKeyPath,
      token: request.params.authToken,
    });

    return {
      id: request.id,
      ok: true,
      data: {
        status,
        authToken: request.params.includeToken
          ? (issuedToken ??
            this.remoteControlManager.getPersistedAuthToken() ??
            undefined)
          : undefined,
      },
    };
  }

  private voiceConnect(
    clientId: string,
    request: RequestFor<"voice_connect">
  ): DaemonResponse {
    if (!this.clientRegistry.hasClient(clientId)) {
      return {
        id: request.id,
        ok: false,
        error: "Voice client is not connected",
      };
    }

    const activeSession = this.metadataStore.getActiveVoiceSession();
    const clientType = request.params.clientType ?? "local-app";

    if (request.params.takeover) {
      for (const [otherClientId, voiceState] of this.voiceClients) {
        if (
          otherClientId !== clientId &&
          voiceState.clientType === clientType
        ) {
          this.voiceClients.delete(otherClientId);
        }
      }
    }

    this.voiceClients.set(clientId, {
      clientType,
      sessionId: activeSession?.id ?? null,
      state: "idle",
    });

    const workspace = activeSession
      ? this.metadataStore.getWorkspace(activeSession.workspaceId)
      : null;

    return {
      id: request.id,
      ok: true,
      data: {
        connected: true,
        sessionId: activeSession?.id ?? null,
        sessionName: activeSession?.name ?? null,
        workspacePath: workspace?.path ?? null,
      },
    };
  }

  private voiceStart(
    _clientId: string,
    request: RequestFor<"voice_start">
  ): DaemonResponse {
    const session = this.resolveSessionRef(
      request.params.sessionId ?? undefined
    );
    if (!session) {
      return {
        id: request.id,
        ok: false,
        error: "No active session for voice start",
      };
    }

    const activeOwner = this.getVoiceOwner(session.id);
    if (activeOwner) {
      return {
        id: request.id,
        ok: true,
        data: {
          started: false,
          reason: "voice_already_active",
          state: activeOwner.voiceState.state,
        },
      };
    }

    const target = this.findIdleVoiceClient(session.id);
    if (!target) {
      return {
        id: request.id,
        ok: true,
        data: { started: false, reason: "voice_not_connected" },
      };
    }

    target.voiceState.sessionId = session.id;
    const sent = this.clientRegistry.sendToClient(target.clientId, {
      event: "voice_start",
      sessionId: session.id,
      data: {
        type: "voice_start" as const,
        sessionId: session.id,
      },
    });
    if (!sent) {
      this.voiceClients.delete(target.clientId);
      return {
        id: request.id,
        ok: true,
        data: { started: false, reason: "voice_not_connected" },
      };
    }

    return {
      id: request.id,
      ok: true,
      data: { started: true, sessionId: session.id },
    };
  }

  private async voiceToolCall(
    clientId: string,
    request: RequestFor<"voice_tool_call">
  ): Promise<DaemonResponse> {
    const { callId, toolName, arguments: argsJson, sessionId } = request.params;
    const voiceClient = this.voiceClients.get(clientId);
    const requestedSession = sessionId
      ? this.resolveSessionRef(sessionId)
      : undefined;

    let voiceSession = requestedSession;
    if (!voiceSession && voiceClient?.sessionId) {
      voiceSession = this.metadataStore.getSession(voiceClient.sessionId);
    }
    if (!voiceSession) {
      voiceSession = this.metadataStore.getActiveVoiceSession();
    }
    if (!voiceSession) {
      return {
        id: request.id,
        ok: false,
        error: "No active voice session for tool execution",
      };
    }

    const activeOwner = this.getVoiceOwner(voiceSession.id);
    if (activeOwner && activeOwner.clientId !== clientId) {
      return {
        id: request.id,
        ok: false,
        error: "Voice session is owned by another client",
      };
    }

    const voiceWorkspace = this.metadataStore.getWorkspace(
      voiceSession.workspaceId
    );
    if (!voiceWorkspace) {
      return {
        id: request.id,
        ok: false,
        error: "Active workspace not found for voice session",
      };
    }

    if (
      typeof request.params.workspacePath === "string" &&
      request.params.workspacePath.length > 0 &&
      resolveWorkspacePath(request.params.workspacePath) !== voiceWorkspace.path
    ) {
      return {
        id: request.id,
        ok: false,
        error: "Voice tool call workspace does not match the active session",
      };
    }

    const result = await executeVoiceTool(
      toolName,
      argsJson,
      voiceWorkspace.path
    );

    return {
      id: request.id,
      ok: true,
      data: { callId, result },
    };
  }

  private voiceState(
    clientId: string,
    request: RequestFor<"voice_state">
  ): DaemonResponse {
    const voiceClient = this.voiceClients.get(clientId);
    if (!voiceClient) {
      return {
        id: request.id,
        ok: false,
        error: "Voice client is not connected",
      };
    }

    const { state, sessionId } = request.params;
    const requestedSession = sessionId
      ? this.resolveSessionRef(sessionId)
      : undefined;
    if (sessionId && !requestedSession) {
      return {
        id: request.id,
        ok: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    const targetSession =
      requestedSession ??
      (voiceClient.sessionId
        ? this.metadataStore.getSession(voiceClient.sessionId)
        : undefined);
    if (!targetSession) {
      return {
        id: request.id,
        ok: false,
        error: "No active session for voice state update",
      };
    }

    const activeOwner = this.getVoiceOwner(targetSession.id);
    if (state !== "idle" && activeOwner && activeOwner.clientId !== clientId) {
      return {
        id: request.id,
        ok: false,
        error: "Voice session is already owned by another client",
      };
    }

    const previousState = voiceClient.state;
    voiceClient.state = state;
    if (state === "idle") {
      voiceClient.sessionId =
        this.metadataStore.getActiveVoiceSessionId() ?? targetSession.id;
    } else if (previousState === "idle") {
      // Lock voice ownership to the session that became active. While voice is
      // active, ignore later session rebinding from workspace attaches.
      voiceClient.sessionId = targetSession.id;
    }

    this.publishVoiceStatus(targetSession.id, state);

    return { id: request.id, ok: true };
  }

  private cleanupClientState(clientId: string): void {
    const detachedSessionIds = this.eventBus.unsubscribe(clientId);
    const voiceClient = this.voiceClients.get(clientId);

    for (const sessionId of detachedSessionIds) {
      const activeOwner = this.getVoiceOwner(sessionId);
      if (
        activeOwner &&
        activeOwner.clientId !== clientId &&
        this.eventBus.getSubscriberCount(sessionId) === 0
      ) {
        this.clientRegistry.sendToClient(activeOwner.clientId, {
          event: "voice_stop",
          sessionId,
          data: {
            type: "voice_stop" as const,
            reason: "cli_exit" as const,
            sessionId,
          },
        });
      }
    }

    if (voiceClient) {
      this.voiceClients.delete(clientId);
      if (voiceClient.sessionId && voiceClient.state !== "idle") {
        this.publishVoiceStatus(voiceClient.sessionId, "idle");
      }
    }
  }
}
