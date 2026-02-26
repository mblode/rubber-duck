import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";
import {
  DEFAULT_SESSION_PREFIX,
  METADATA_PATH,
  METADATA_VERSION,
} from "../constants.js";
import type { DaemonMetadata, Session, Workspace } from "../types.js";
import { generateId, workspaceId } from "../utils.js";

export class MetadataStore {
  private readonly data: DaemonMetadata;

  constructor() {
    this.data = this.load();
  }

  private load(): DaemonMetadata {
    try {
      const raw = readFileSync(METADATA_PATH, "utf-8");
      return JSON.parse(raw) as DaemonMetadata;
    } catch {
      return {
        version: METADATA_VERSION,
        workspaces: [],
        sessions: [],
        activeVoiceSessionId: null,
      };
    }
  }

  private save(): void {
    const dir = dirname(METADATA_PATH);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    const tmp = `${METADATA_PATH}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    renameSync(tmp, METADATA_PATH);
  }

  // Workspace methods

  getWorkspace(id: string): Workspace | undefined {
    return this.data.workspaces.find((w) => w.id === id);
  }

  getWorkspaceByPath(path: string): Workspace | undefined {
    return this.data.workspaces.find((w) => w.path === path);
  }

  addWorkspace(path: string): Workspace {
    const existing = this.getWorkspaceByPath(path);
    if (existing) {
      return existing;
    }
    const workspace: Workspace = {
      id: workspaceId(path),
      path,
      createdAt: new Date().toISOString(),
      lastActiveSessionId: null,
    };
    this.data.workspaces.push(workspace);
    this.save();
    return workspace;
  }

  updateWorkspace(
    id: string,
    updates: Partial<Workspace>
  ): Workspace | undefined {
    const workspace = this.getWorkspace(id);
    if (!workspace) {
      return undefined;
    }
    Object.assign(workspace, updates);
    this.save();
    return workspace;
  }

  // Session methods

  getSession(id: string): Session | undefined {
    return this.data.sessions.find((s) => s.id === id);
  }

  getSessionByName(name: string, wsId?: string): Session | undefined {
    const matches = this.data.sessions.filter((s) => {
      if (wsId && s.workspaceId !== wsId) {
        return false;
      }
      return s.name.toLowerCase() === name.toLowerCase();
    });
    if (matches.length === 1) {
      return matches[0];
    }
    return undefined;
  }

  resolveSession(ref: string, wsId?: string): Session | undefined {
    // Try exact ID match
    const byId = this.getSession(ref);
    if (byId) {
      return byId;
    }
    // Try exact name match
    const byName = this.getSessionByName(ref, wsId);
    if (byName) {
      return byName;
    }
    // Try prefix match on name
    const candidates = this.data.sessions.filter((s) => {
      if (wsId && s.workspaceId !== wsId) {
        return false;
      }
      return s.name.toLowerCase().startsWith(ref.toLowerCase());
    });
    if (candidates.length === 1) {
      return candidates[0];
    }
    return undefined;
  }

  getSessionsForWorkspace(wsId: string): Session[] {
    return this.data.sessions.filter((s) => s.workspaceId === wsId);
  }

  getAllSessions(): Session[] {
    return [...this.data.sessions];
  }

  addSession(wsId: string, name?: string, piSessionFile?: string): Session {
    const existingSessions = this.getSessionsForWorkspace(wsId);
    const sessionName =
      name ?? `${DEFAULT_SESSION_PREFIX}-${existingSessions.length + 1}`;
    const session: Session = {
      id: generateId(),
      workspaceId: wsId,
      name: sessionName,
      piSessionFile: piSessionFile ?? "",
      createdAt: new Date().toISOString(),
      lastActiveAt: new Date().toISOString(),
      isVoiceActive: false,
    };
    this.data.sessions.push(session);
    this.save();
    return session;
  }

  updateSession(id: string, updates: Partial<Session>): Session | undefined {
    const session = this.getSession(id);
    if (!session) {
      return undefined;
    }
    Object.assign(session, updates);
    this.save();
    return session;
  }

  // Active voice session

  getActiveVoiceSessionId(): string | null {
    return this.data.activeVoiceSessionId;
  }

  getActiveVoiceSession(): Session | undefined {
    if (!this.data.activeVoiceSessionId) {
      return undefined;
    }
    return this.getSession(this.data.activeVoiceSessionId);
  }

  setActiveVoiceSession(sessionId: string): void {
    this.data.activeVoiceSessionId = sessionId;
    this.save();
  }

  getData(): DaemonMetadata {
    return structuredClone(this.data);
  }
}
