import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DaemonClient } from "../client.js";
import type { DaemonEvent, RemoteControlStatus } from "../types.js";

interface Harness {
  clientRegistry: {
    registerClient(registration: {
      close: () => void;
      send: (_message: unknown) => void;
      transport: "socket" | "remote_ws";
    }): string;
    unregisterClient(clientId: string): void;
  };
  processManager: { killAll(): Promise<void> };
  requestHandler: {
    handle(
      clientId: string,
      request: Record<string, unknown>
    ): Promise<Record<string, unknown>>;
  };
  remoteControlManager: {
    configure(params: Record<string, unknown>): Promise<{
      issuedToken: string | null;
      status: RemoteControlStatus;
    }>;
    stop(): Promise<void>;
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function httpRpc(
  httpUrl: string,
  token: string | null | undefined,
  request: Record<string, unknown>,
  clientId?: string
): Promise<{ body: Record<string, unknown>; status: number }> {
  const response = await fetch(`${httpUrl}/rpc`, {
    method: "POST",
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(clientId ? { "x-rubber-duck-client-id": clientId } : {}),
      "content-type": "application/json",
    },
    body: JSON.stringify(request),
  });

  return {
    status: response.status,
    body: (await response.json()) as Record<string, unknown>,
  };
}

function findEvent(
  events: DaemonEvent[],
  eventName: string
): DaemonEvent | undefined {
  return events.find((event) => event.event === eventName);
}

describe("remote daemon control plane", () => {
  let tmpRoot = "";
  let harness: Harness | null = null;

  beforeEach(async () => {
    tmpRoot = await mkdtemp(join(tmpdir(), "duck-remote-"));
    process.env.RUBBER_DUCK_APP_SUPPORT = tmpRoot;
    vi.resetModules();

    const [
      { ClientRegistry },
      { DaemonConfigStore },
      { EventBus },
      { MetadataStore },
      { PiProcessManager },
      { RemoteControlManager },
      { RequestHandler },
    ] = await Promise.all([
      import("../daemon/client-registry.js"),
      import("../daemon/config-store.js"),
      import("../daemon/event-bus.js"),
      import("../daemon/metadata-store.js"),
      import("../daemon/pi-process-manager.js"),
      import("../daemon/remote-control.js"),
      import("../daemon/request-handler.js"),
    ]);

    const configStore = new DaemonConfigStore();
    const metadataStore = new MetadataStore();
    const eventBus = new EventBus();
    const clientRegistry = new ClientRegistry();
    const processManager = new PiProcessManager(eventBus);
    const remoteControlManager = new RemoteControlManager(
      configStore,
      clientRegistry,
      () => undefined
    );
    const requestHandler = new RequestHandler(
      metadataStore,
      processManager,
      eventBus,
      clientRegistry,
      remoteControlManager
    );

    remoteControlManager.setRequestHandler((clientId, request) =>
      requestHandler.handle(clientId, request)
    );
    remoteControlManager.setDisconnectHandler((clientId) =>
      requestHandler.handleDisconnect(clientId)
    );

    harness = {
      clientRegistry,
      processManager,
      requestHandler,
      remoteControlManager,
    };
  });

  afterEach(async () => {
    await harness?.remoteControlManager.stop();
    await harness?.processManager.killAll();
    harness = null;
    process.env.RUBBER_DUCK_APP_SUPPORT = undefined;
    vi.resetModules();
    if (tmpRoot) {
      await rm(tmpRoot, { recursive: true, force: true });
    }
  });

  it("authenticates remote RPCs and preserves voice routing for the active voice session", async () => {
    if (!harness) {
      throw new Error("Harness not initialized");
    }

    const workspaceA = join(tmpRoot, "workspace-a");
    const workspaceB = join(tmpRoot, "workspace-b");
    await mkdir(workspaceA, { recursive: true });
    await mkdir(workspaceB, { recursive: true });
    await writeFile(join(workspaceA, "voice-test.txt"), "workspace-a-content");
    await writeFile(join(workspaceB, "voice-test.txt"), "workspace-b-content");

    const configured = await harness.remoteControlManager.configure({
      enabled: true,
      port: 0,
      rotateToken: true,
    });

    expect(configured.issuedToken).toBeTruthy();
    expect(configured.status.httpUrl).toBeTruthy();
    expect(configured.status.wsUrl).toBeTruthy();

    const unauthorized = await httpRpc(configured.status.httpUrl ?? "", null, {
      id: "ping-unauthorized",
      method: "ping",
      params: {},
    });
    expect(unauthorized.status).toBe(401);

    const remoteClient = await DaemonClient.connect({
      authToken: configured.issuedToken ?? undefined,
      remoteUrl: configured.status.httpUrl ?? undefined,
    });

    const events: DaemonEvent[] = [];
    remoteClient.onEvent((event) => {
      events.push(event);
    });

    const voiceConnect = await remoteClient.request("voice_connect", {
      clientType: "remote-web",
      clientVersion: "test",
      takeover: true,
    });
    expect(voiceConnect.ok).toBe(true);

    const attachA = await remoteClient.request("attach", { path: workspaceA });
    expect(attachA.ok).toBe(true);
    const sessionA = (attachA.data as { session: { id: string } }).session.id;

    const voiceStart = await remoteClient.request("voice_start", {
      sessionId: sessionA,
    });
    expect(voiceStart.ok).toBe(true);
    expect((voiceStart.data as { started: boolean }).started).toBe(true);

    const voiceState = await remoteClient.request("voice_state", {
      sessionId: sessionA,
      state: "listening",
    });
    expect(voiceState.ok).toBe(true);

    const attachB = await httpRpc(
      configured.status.httpUrl ?? "",
      configured.issuedToken,
      {
        id: "attach-b",
        method: "attach",
        params: { path: workspaceB },
      }
    );
    expect(attachB.status).toBe(200);

    await delay(150);
    const switchedEvent = events.find(
      (event) =>
        event.event === "voice_session_changed" && event.sessionId !== sessionA
    );
    expect(switchedEvent).toBeUndefined();

    const sayResponse = await httpRpc(
      configured.status.httpUrl ?? "",
      configured.issuedToken,
      {
        id: "say-a",
        method: "say",
        params: { message: "hello", sessionId: sessionA },
      }
    );
    expect(sayResponse.status).toBe(200);

    await delay(150);
    const voiceSay = findEvent(events, "voice_say");
    expect(voiceSay).toBeDefined();
    expect(voiceSay?.sessionId).toBe(sessionA);
    expect(voiceSay?.data).toEqual({ text: "hello" });

    const toolCall = await remoteClient.request("voice_tool_call", {
      arguments: JSON.stringify({ path: "voice-test.txt" }),
      callId: "call-1",
      toolName: "read_file",
      workspacePath: workspaceA,
    });
    expect(toolCall.ok).toBe(true);
    expect((toolCall.data as { result: string }).result).toBe(
      "workspace-a-content"
    );

    remoteClient.close();
  });

  it("exposes remote status over authenticated HTTP after enable", async () => {
    if (!harness) {
      throw new Error("Harness not initialized");
    }

    const configured = await harness.remoteControlManager.configure({
      enabled: true,
      port: 0,
      rotateToken: true,
    });

    const response = await fetch(`${configured.status.httpUrl}/status`, {
      headers: {
        Authorization: `Bearer ${configured.issuedToken}`,
      },
    });

    expect(response.status).toBe(200);
    const body = (await response.json()) as RemoteControlStatus;
    expect(body.enabled).toBe(true);
    expect(body.listening).toBe(true);
    expect(body.connectedClients).toBe(0);

    const queryAuthResponse = await fetch(
      `${configured.status.httpUrl}/status?token=${configured.issuedToken}`
    );
    expect(queryAuthResponse.status).toBe(401);
  });

  it("only reveals pairing tokens and configuration controls to local socket clients", async () => {
    if (!harness) {
      throw new Error("Harness not initialized");
    }

    const configured = await harness.remoteControlManager.configure({
      enabled: true,
      port: 0,
      rotateToken: true,
    });

    const localClientId = harness.clientRegistry.registerClient({
      transport: "socket",
      send: () => undefined,
      close: () => undefined,
    });

    const localStatus = await harness.requestHandler.handle(localClientId, {
      id: "local-status",
      method: "remote_status",
      params: { includeToken: true },
    });

    expect(localStatus.ok).toBe(true);
    expect(
      (localStatus.data as { authToken?: string }).authToken
    ).toBe(configured.issuedToken);

    const remoteStatus = await httpRpc(
      configured.status.httpUrl ?? "",
      configured.issuedToken,
      {
        id: "remote-status",
        method: "remote_status",
        params: { includeToken: true },
      }
    );

    expect(remoteStatus.status).toBe(200);
    expect(
      (remoteStatus.body.data as { authToken?: string | null }).authToken
    ).toBeUndefined();

    const remoteConfigure = await httpRpc(
      configured.status.httpUrl ?? "",
      configured.issuedToken,
      {
        id: "remote-configure",
        method: "remote_configure",
        params: {
          enabled: true,
          rotateToken: true,
          includeToken: true,
        },
      }
    );

    expect(remoteConfigure.status).toBe(400);
    expect(remoteConfigure.body.error).toContain("local clients");

    harness.clientRegistry.unregisterClient(localClientId);
  });

  it("serves the remote web shell and conversation history endpoints", async () => {
    if (!harness) {
      throw new Error("Harness not initialized");
    }

    const workspace = join(tmpRoot, "workspace-history");
    const sessionsDir = join(tmpRoot, "sessions");
    await mkdir(workspace, { recursive: true });
    await mkdir(sessionsDir, { recursive: true });

    const configured = await harness.remoteControlManager.configure({
      enabled: true,
      port: 0,
      rotateToken: true,
    });

    const attach = await httpRpc(
      configured.status.httpUrl ?? "",
      configured.issuedToken,
      {
        id: "attach-history",
        method: "attach",
        params: { path: workspace },
      }
    );

    expect(attach.status).toBe(200);
    const sessionId = (attach.body.data as { session: { id: string } }).session.id;

    await writeFile(
      join(sessionsDir, `${sessionId}.jsonl`),
      [
        JSON.stringify({
          timestamp: "2026-03-10T00:00:00Z",
          sessionID: sessionId,
          text: "Explain the daemon layout.",
          type: "user_text",
        }),
        JSON.stringify({
          metadata: { source: "test" },
          sessionID: sessionId,
          text: "The daemon keeps a metadata store and a process manager.",
          timestamp: "2026-03-10T00:00:01Z",
          type: "assistant_text",
        }),
      ].join("\n")
    );

    const shellResponse = await fetch(`${configured.status.httpUrl}/`);
    expect(shellResponse.status).toBe(200);
    expect(shellResponse.headers.get("content-type")).toContain("text/html");
    expect(await shellResponse.text()).toContain("Rubber Duck Remote");

    const historyResponse = await fetch(
      `${configured.status.httpUrl}/history?sessionId=${sessionId}&limit=2`,
      {
        headers: {
          Authorization: `Bearer ${configured.issuedToken}`,
        },
      }
    );

    expect(historyResponse.status).toBe(200);
    const historyBody = (await historyResponse.json()) as {
      events: Array<{ text?: string; type: string }>;
      sessionId: string;
    };
    expect(historyBody.sessionId).toBe(sessionId);
    expect(historyBody.events).toHaveLength(2);
    expect(historyBody.events[0]?.type).toBe("user_text");
    expect(historyBody.events[1]?.text).toContain("metadata store");
  });
});
