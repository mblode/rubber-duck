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
} from "../types.js";
import { findGitRoot, resolveWorkspacePath } from "../utils.js";
import type { EventBus } from "./event-bus.js";
import type { MetadataStore } from "./metadata-store.js";
import type { PiProcessManager } from "./pi-process-manager.js";
import type { SocketServer } from "./socket-server.js";
import { executeVoiceTool } from "./voice-tools.js";

interface RequestFor<M extends keyof DaemonRequestMap> {
  id: string;
  method: M;
  params: DaemonRequestMap[M];
}

const startedAt = Date.now();

export class RequestHandler {
  private readonly metadataStore: MetadataStore;
  private readonly processManager: PiProcessManager;
  private readonly eventBus: EventBus;
  private readonly socketServer: SocketServer;
  private voiceClientId: string | null = null;

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
        case "abort":
          return await this.abort(request);
        case "doctor":
          return this.doctor(request);
        case "get_state":
          return await this.getState(request);
        case "voice_connect":
          return this.voiceConnect(clientId, request);
        case "voice_tool_call":
          return await this.voiceToolCall(request);
        case "voice_state":
          return this.voiceState(request);
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
        clients: this.socketServer.getClientCount(),
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

    // Notify the Swift voice app immediately so it doesn't have to wait for metadata.json polling
    if (this.voiceClientId) {
      this.socketServer.sendToClient(this.voiceClientId, {
        event: "voice_session_changed",
        sessionId: session.id,
        data: {
          type: "voice_session_changed" as const,
          sessionId: session.id,
          sessionName: session.name,
          workspacePath: workspace.path,
        },
      });
    }

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
    this.eventBus.unsubscribe(clientId);
    if (clientId === this.voiceClientId) {
      this.voiceClientId = null;
    }
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

    // Publish user utterance event for CLI stream rendering
    this.eventBus.publish(session.id, {
      type: "message_start",
      message: {
        role: "user",
        content: message,
        timestamp: new Date().toISOString(),
      },
    } as PiEvent);

    // If voice app is connected, route to voice agent instead of Pi
    if (this.voiceClientId) {
      this.socketServer.sendToClient(this.voiceClientId, {
        event: "voice_say",
        sessionId: session.id,
        data: { text: message },
      });
      return {
        id: request.id,
        ok: true,
        data: { sessionId: session.id, sessionName: session.name },
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

  private voiceConnect(
    clientId: string,
    request: RequestFor<"voice_connect">
  ): DaemonResponse {
    this.voiceClientId = clientId;

    const activeSession = this.metadataStore.getActiveVoiceSession();
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

  private async voiceToolCall(
    request: RequestFor<"voice_tool_call">
  ): Promise<DaemonResponse> {
    const {
      callId,
      toolName,
      arguments: argsJson,
      workspacePath,
    } = request.params;

    const activeSession = this.metadataStore.getActiveVoiceSession();
    if (!activeSession) {
      return {
        id: request.id,
        ok: false,
        error: "No active voice session for tool execution",
      };
    }

    const activeWorkspace = this.metadataStore.getWorkspace(
      activeSession.workspaceId
    );
    if (!activeWorkspace) {
      return {
        id: request.id,
        ok: false,
        error: "Active workspace not found for voice session",
      };
    }

    // `workspacePath` from the voice client is advisory only. Use the active
    // daemon workspace as the execution source-of-truth so minor path
    // normalization differences (symlinks, casing, trailing slash) do not
    // cause false tool failures mid-conversation.
    void workspacePath;

    const result = await executeVoiceTool(
      toolName,
      argsJson,
      activeWorkspace.path
    );

    return {
      id: request.id,
      ok: true,
      data: { callId, result },
    };
  }

  private voiceState(request: RequestFor<"voice_state">): DaemonResponse {
    const { state, sessionId } = request.params;

    const session = this.resolveSessionRef(sessionId);

    if (session) {
      // Publish a setStatus event so `duck follow` clients can see voice activity.
      this.eventBus.publish(session.id, {
        type: "extension_ui_request",
        id: `voice-state-${Date.now()}`,
        method: "setStatus",
        message: `voice:${state}`,
      } as PiEvent);
    }

    return { id: request.id, ok: true };
  }
}
