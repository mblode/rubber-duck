import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import {
  createServer as createHttpServer,
  type Server as HttpServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import {
  createServer as createHttpsServer,
  type Server as HttpsServer,
} from "node:https";
import type { AddressInfo } from "node:net";
import { basename, extname, join, normalize } from "node:path";
import { fileURLToPath, URL } from "node:url";
import { type RawData, WebSocket, WebSocketServer } from "ws";
import { APP_SUPPORT, REMOTE_AUTH_TOKEN_PATH } from "../constants.js";
import type {
  DaemonEvent,
  DaemonRequest,
  DaemonResponse,
  RemoteControlStatus,
} from "../types.js";
import { generateId } from "../utils.js";
import {
  createRemoteAuthTokenRecord,
  verifyRemoteAuthToken,
} from "./auth-token.js";
import type { ClientRegistry } from "./client-registry.js";
import type { DaemonConfigStore, RemoteControlConfig } from "./config-store.js";

type RequestHandler = (
  clientId: string,
  request: DaemonRequest
) => Promise<DaemonResponse>;

type DisconnectHandler = (clientId: string) => void;

export interface RemoteControlConfigureOptions {
  enabled?: boolean;
  host?: string;
  port?: number;
  rotateToken?: boolean;
  tlsCertPath?: string | null;
  tlsKeyPath?: string | null;
  token?: string;
}

function persistRemoteAuthToken(token: string): void {
  mkdirSync(APP_SUPPORT, { recursive: true });
  writeFileSync(REMOTE_AUTH_TOKEN_PATH, `${token}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  chmodSync(REMOTE_AUTH_TOKEN_PATH, 0o600);
}

function readPersistedRemoteAuthToken(): string | null {
  try {
    if (!existsSync(REMOTE_AUTH_TOKEN_PATH)) {
      return null;
    }

    const token = readFileSync(REMOTE_AUTH_TOKEN_PATH, "utf8").trim();
    return token.length > 0 ? token : null;
  } catch {
    return null;
  }
}

const WEB_CLIENT_ROOT_CANDIDATES = [
  fileURLToPath(new URL("../web-client/", import.meta.url)),
  fileURLToPath(new URL("./web-client/", import.meta.url)),
];

const JSON_CACHE_CONTROL = "no-store";
const SESSION_ID_PATTERN = /^[A-Za-z0-9_-]+$/;

function resolveWebClientRoot(): string | null {
  for (const candidate of WEB_CLIENT_ROOT_CANDIDATES) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function contentTypeForPath(filePath: string): string {
  switch (extname(filePath).toLowerCase()) {
    case ".css":
      return "text/css; charset=utf-8";
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "application/javascript; charset=utf-8";
    case ".json":
    case ".webmanifest":
      return "application/json; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    default:
      return "application/octet-stream";
  }
}

function isSafeAssetPath(requestPath: string): boolean {
  const normalizedPath = normalize(requestPath);
  return !(normalizedPath.startsWith("..") || normalizedPath.includes("../"));
}

function setCorsHeaders(response: ServerResponse): void {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, X-Rubber-Duck-Client-Id"
  );
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.setHeader("Permissions-Policy", "microphone=(self)");
  response.setHeader("Referrer-Policy", "same-origin");
  response.setHeader("X-Content-Type-Options", "nosniff");
}

function readJsonBody(request: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];

    request.on("data", (chunk: Buffer) => {
      chunks.push(chunk);
      const size = chunks.reduce((sum, value) => sum + value.length, 0);
      if (size > 1_000_000) {
        reject(new Error("Request body too large"));
        request.destroy();
      }
    });

    request.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf-8");
        resolve(raw.length > 0 ? JSON.parse(raw) : {});
      } catch (error) {
        reject(error);
      }
    });

    request.on("error", reject);
  });
}

function rawDataToString(data: RawData): string {
  if (typeof data === "string") {
    return data;
  }
  return rawDataToBuffer(data).toString("utf8");
}

function rawDataToBuffer(data: Exclude<RawData, string>): Buffer {
  if (Buffer.isBuffer(data)) {
    return data;
  }
  if (Array.isArray(data)) {
    return Buffer.concat(data.map((value) => rawDataToBuffer(value)));
  }
  return Buffer.from(data);
}

export class RemoteControlManager {
  private readonly configStore: DaemonConfigStore;
  private readonly clientRegistry: ClientRegistry;
  private readonly log: (message: string) => void;
  private requestHandler: RequestHandler | null = null;
  private disconnectHandler: DisconnectHandler | null = null;
  private httpServer: HttpServer | HttpsServer | null = null;
  private websocketServer: WebSocketServer | null = null;
  private readonly remoteClientIds = new Set<string>();
  private lastError: string | null = null;
  private actualPort: number | null = null;
  private tlsEnabled = false;

  constructor(
    configStore: DaemonConfigStore,
    clientRegistry: ClientRegistry,
    log: (message: string) => void
  ) {
    this.configStore = configStore;
    this.clientRegistry = clientRegistry;
    this.log = log;
  }

  setRequestHandler(handler: RequestHandler): void {
    this.requestHandler = handler;
  }

  setDisconnectHandler(handler: DisconnectHandler): void {
    this.disconnectHandler = handler;
  }

  async start(): Promise<void> {
    await this.reconcile();
  }

  async stop(): Promise<void> {
    await this.stopServer();
  }

  async configure(
    options: RemoteControlConfigureOptions
  ): Promise<{ issuedToken: string | null; status: RemoteControlStatus }> {
    const config = this.configStore.getConfig();
    const remoteUpdates: Partial<RemoteControlConfig> = {};
    let issuedToken: string | null = null;

    if (typeof options.enabled === "boolean") {
      remoteUpdates.enabled = options.enabled;
    }
    if (typeof options.host === "string" && options.host.trim().length > 0) {
      remoteUpdates.host = options.host.trim();
    }
    if (typeof options.port === "number") {
      remoteUpdates.port = options.port;
    }
    if (options.tlsCertPath !== undefined) {
      remoteUpdates.tlsCertPath = options.tlsCertPath?.trim() || null;
    }
    if (options.tlsKeyPath !== undefined) {
      remoteUpdates.tlsKeyPath = options.tlsKeyPath?.trim() || null;
    }

    const shouldIssueToken =
      options.rotateToken === true ||
      (typeof options.token === "string" && options.token.trim().length > 0) ||
      ((options.enabled ?? config.remote.enabled) &&
        !config.remote.authTokenHash &&
        !config.remote.authTokenSalt);

    if (shouldIssueToken) {
      const tokenRecord = createRemoteAuthTokenRecord(options.token);
      remoteUpdates.authTokenHash = tokenRecord.hash;
      remoteUpdates.authTokenSalt = tokenRecord.salt;
      remoteUpdates.authTokenUpdatedAt = tokenRecord.updatedAt;
      issuedToken = tokenRecord.issuedToken;
      persistRemoteAuthToken(tokenRecord.issuedToken);
    }

    this.configStore.updateConfig({
      remote: remoteUpdates,
    });

    await this.reconcile();

    return {
      issuedToken,
      status: this.getStatus(),
    };
  }

  getStatus(): RemoteControlStatus {
    const config = this.configStore.getConfig();
    const { remote } = config;
    const port = this.actualPort ?? remote.port;
    const protocol = this.tlsEnabled ? "https" : "http";
    const wsProtocol = this.tlsEnabled ? "wss" : "ws";
    const listening = this.httpServer !== null && this.actualPort !== null;

    return {
      enabled: remote.enabled,
      listening,
      host: remote.host,
      port,
      protocol,
      tlsEnabled: this.tlsEnabled,
      httpUrl: listening ? `${protocol}://${remote.host}:${port}` : null,
      wsUrl: listening ? `${wsProtocol}://${remote.host}:${port}/ws` : null,
      tokenConfigured: !!remote.authTokenHash && !!remote.authTokenSalt,
      tokenUpdatedAt: remote.authTokenUpdatedAt,
      lastError: this.lastError,
      connectedClients: this.remoteClientIds.size,
    };
  }

  getPersistedAuthToken(): string | null {
    const config = this.configStore.getConfig();
    const token = readPersistedRemoteAuthToken();
    if (!token) {
      return null;
    }

    return verifyRemoteAuthToken(token, config.remote) ? token : null;
  }

  private async reconcile(): Promise<void> {
    const config = this.configStore.getConfig();
    const { remote } = config;

    await this.stopServer();

    if (!remote.enabled) {
      this.lastError = null;
      return;
    }

    if (!(remote.authTokenHash && remote.authTokenSalt)) {
      this.lastError = "Remote control auth token is not configured";
      return;
    }

    try {
      await this.startServer(remote);
      this.lastError = null;
      this.log(
        `Remote control listening on ${this.tlsEnabled ? "https" : "http"}://${remote.host}:${this.actualPort ?? remote.port}`
      );
    } catch (error) {
      this.lastError = error instanceof Error ? error.message : String(error);
      this.log(`Remote control failed to start: ${this.lastError}`);
    }
  }

  private async startServer(config: RemoteControlConfig): Promise<void> {
    const tlsEnabled =
      !!config.tlsCertPath?.trim() && !!config.tlsKeyPath?.trim();
    if (!!config.tlsCertPath !== !!config.tlsKeyPath) {
      throw new Error("Remote TLS requires both cert and key paths");
    }

    this.tlsEnabled = tlsEnabled;
    this.httpServer = tlsEnabled
      ? createHttpsServer({
          cert: readFileSync(config.tlsCertPath ?? "", "utf-8"),
          key: readFileSync(config.tlsKeyPath ?? "", "utf-8"),
        })
      : createHttpServer();

    this.httpServer.on("request", (request, response) =>
      this.handleHttpRequest(request, response)
    );

    this.websocketServer = new WebSocketServer({ noServer: true });
    this.websocketServer.on("connection", (socket, request) =>
      this.handleWebSocketConnection(socket, request)
    );

    this.httpServer.on("upgrade", (request, socket, head) => {
      const requestUrl = new URL(
        request.url ?? "/",
        `${this.tlsEnabled ? "https" : "http"}://${request.headers.host ?? config.host}`
      );

      if (requestUrl.pathname !== "/ws") {
        socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
        socket.destroy();
        return;
      }

      if (!this.isAuthorized(request, requestUrl)) {
        socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
        socket.destroy();
        return;
      }

      this.websocketServer?.handleUpgrade(
        request,
        socket,
        head,
        (websocket) => {
          this.websocketServer?.emit("connection", websocket, request);
        }
      );
    });

    await new Promise<void>((resolve, reject) => {
      this.httpServer?.once("error", reject);
      this.httpServer?.listen(config.port, config.host, () => {
        this.httpServer?.removeListener("error", reject);
        resolve();
      });
    });

    const address = this.httpServer.address();
    if (!address || typeof address === "string") {
      throw new Error("Remote control server did not expose a TCP address");
    }

    this.actualPort = (address as AddressInfo).port;
  }

  private async stopServer(): Promise<void> {
    const websocketServer = this.websocketServer;
    this.websocketServer = null;

    if (websocketServer) {
      for (const client of websocketServer.clients) {
        client.close();
      }
      websocketServer.close();
    }

    for (const clientId of this.remoteClientIds) {
      this.clientRegistry.unregisterClient(clientId);
      this.disconnectHandler?.(clientId);
      this.remoteClientIds.delete(clientId);
    }

    const httpServer = this.httpServer;
    this.httpServer = null;
    this.actualPort = null;
    this.tlsEnabled = false;

    if (!httpServer) {
      return;
    }

    await new Promise<void>((resolve) => {
      httpServer.close(() => resolve());
    });
  }

  private isAuthorized(request: IncomingMessage, _requestUrl?: URL): boolean {
    const authHeader = request.headers.authorization;
    const bearerToken = authHeader?.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : null;

    return verifyRemoteAuthToken(
      bearerToken,
      this.configStore.getConfig().remote
    );
  }

  private async handleHttpRequest(
    request: IncomingMessage,
    response: ServerResponse
  ): Promise<void> {
    setCorsHeaders(response);

    if (request.method === "OPTIONS") {
      response.statusCode = 204;
      response.end();
      return;
    }

    const requestUrl = new URL(
      request.url ?? "/",
      `${this.tlsEnabled ? "https" : "http"}://${request.headers.host ?? "127.0.0.1"}`
    );

    if (requestUrl.pathname === "/health" && request.method === "GET") {
      this.writeJson(response, 200, { ok: true, status: this.getStatus() });
      return;
    }

    if (
      request.method === "GET" &&
      this.isWebClientRequest(requestUrl.pathname)
    ) {
      this.serveWebClientAsset(requestUrl, response);
      return;
    }

    if (!this.isAuthorized(request, requestUrl)) {
      this.writeJson(response, 401, { error: "Unauthorized" });
      return;
    }

    if (requestUrl.pathname === "/status" && request.method === "GET") {
      this.writeJson(response, 200, this.getStatus());
      return;
    }

    if (requestUrl.pathname === "/history" && request.method === "GET") {
      this.handleHistoryRequest(requestUrl, response);
      return;
    }

    if (requestUrl.pathname !== "/rpc" || request.method !== "POST") {
      this.writeJson(response, 404, { error: "Not found" });
      return;
    }

    await this.handleRpcRequest(request, response);
  }

  private isWebClientRequest(pathname: string): boolean {
    if (pathname === "/") {
      return true;
    }

    if (pathname.startsWith("/ws")) {
      return false;
    }

    return pathname.startsWith("/assets/") || pathname.includes(".");
  }

  private serveWebClientAsset(requestUrl: URL, response: ServerResponse): void {
    const webClientRoot = resolveWebClientRoot();
    if (!webClientRoot) {
      this.writeJson(response, 404, {
        error: "Remote web client bundle is not available",
      });
      return;
    }

    const relativePath =
      requestUrl.pathname === "/"
        ? "index.html"
        : decodeURIComponent(requestUrl.pathname.slice(1));

    if (!isSafeAssetPath(relativePath)) {
      this.writeJson(response, 404, { error: "Not found" });
      return;
    }

    const resolvedPath = join(webClientRoot, relativePath);
    if (!existsSync(resolvedPath)) {
      this.writeJson(response, 404, { error: "Not found" });
      return;
    }

    try {
      let body = readFileSync(resolvedPath);
      response.statusCode = 200;
      response.setHeader("Content-Type", contentTypeForPath(resolvedPath));
      response.setHeader(
        "Cache-Control",
        basename(resolvedPath) === "sw.js" ? "no-cache" : "public, max-age=300"
      );

      if (basename(resolvedPath) === "index.html") {
        const injected = readFileSync(resolvedPath, "utf-8").replace(
          "</body>",
          `${this.remoteBootstrapScript(requestUrl)}</body>`
        );
        body = Buffer.from(injected, "utf-8");
      }

      response.end(body);
    } catch (error) {
      this.writeJson(response, 500, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private remoteBootstrapScript(requestUrl: URL): string {
    const origin = `${this.tlsEnabled ? "https" : "http"}://${requestUrl.host}`;
    const webSocketURL = `${this.tlsEnabled ? "wss" : "ws"}://${requestUrl.host}/ws`;
    const payload = JSON.stringify({
      daemon: {
        httpUrl: origin,
      },
      sideband: {
        url: webSocketURL,
      },
    });

    return `<script>globalThis.__RUBBER_DUCK_REMOTE_CONFIG__=${payload};</script>`;
  }

  private handleHistoryRequest(
    requestUrl: URL,
    response: ServerResponse
  ): void {
    const sessionId = requestUrl.searchParams.get("sessionId")?.trim();
    const limitRaw = Number.parseInt(
      requestUrl.searchParams.get("limit") ?? "200",
      10
    );
    const limit = Number.isFinite(limitRaw)
      ? Math.min(Math.max(limitRaw, 1), 1000)
      : 200;

    if (!(sessionId && SESSION_ID_PATTERN.test(sessionId))) {
      this.writeJson(response, 400, {
        error: "A valid sessionId query parameter is required",
      });
      return;
    }

    const historyPath = join(APP_SUPPORT, "sessions", `${sessionId}.jsonl`);
    if (!existsSync(historyPath)) {
      this.writeJson(response, 404, {
        error: `History not found for session ${sessionId}`,
      });
      return;
    }

    try {
      const lines = readFileSync(historyPath, "utf-8")
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .slice(-limit);

      const events = lines.flatMap((line) => {
        try {
          return [JSON.parse(line) as Record<string, unknown>];
        } catch {
          return [];
        }
      });

      this.writeJson(response, 200, {
        events,
        sessionId,
      });
    } catch (error) {
      this.writeJson(response, 500, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private async handleRpcRequest(
    request: IncomingMessage,
    response: ServerResponse
  ): Promise<void> {
    if (!this.requestHandler) {
      this.writeJson(response, 503, {
        error: "Remote control handler not ready",
      });
      return;
    }

    try {
      const body = (await readJsonBody(request)) as DaemonRequest;
      const requestedClientId = request.headers["x-rubber-duck-client-id"];
      const headerClientId =
        typeof requestedClientId === "string" &&
        requestedClientId.trim().length > 0
          ? requestedClientId.trim()
          : null;

      if (headerClientId && !this.clientRegistry.hasClient(headerClientId)) {
        this.writeJson(response, 400, { error: "Unknown client id" });
        return;
      }

      const clientId = headerClientId ?? `remote-http-${generateId()}`;
      const daemonResponse = await this.requestHandler(clientId, body);

      this.writeJson(response, daemonResponse.ok ? 200 : 400, daemonResponse);
    } catch (error) {
      this.writeJson(response, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private handleWebSocketConnection(
    socket: WebSocket,
    request: IncomingMessage
  ): void {
    const clientId = this.clientRegistry.registerClient({
      transport: "remote_ws",
      send: (message) => {
        if (socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify(message));
        }
      },
      close: () => {
        if (
          socket.readyState === WebSocket.OPEN ||
          socket.readyState === WebSocket.CONNECTING
        ) {
          socket.close();
        }
      },
    });

    this.remoteClientIds.add(clientId);

    const sendReadyMessage = () => {
      const hostHeader = request.headers.host ?? "127.0.0.1";
      const protocol = this.tlsEnabled ? "wss" : "ws";
      const readyEvent: DaemonEvent = {
        event: "remote_ready",
        sessionId: "remote-control",
        data: {
          type: "remote_ready",
          clientId,
          websocketUrl: `${protocol}://${hostHeader}/ws`,
        },
      };
      this.clientRegistry.sendToClient(clientId, readyEvent);
    };

    const cleanup = () => {
      if (!this.remoteClientIds.has(clientId)) {
        return;
      }

      this.remoteClientIds.delete(clientId);
      this.clientRegistry.unregisterClient(clientId);
      this.disconnectHandler?.(clientId);
    };

    socket.on("message", (data: RawData) => {
      this.handleWebSocketMessage(clientId, socket, data).catch(
        () => undefined
      );
    });
    socket.on("close", cleanup);
    socket.on("error", cleanup);

    sendReadyMessage();
  }

  private async handleWebSocketMessage(
    clientId: string,
    socket: WebSocket,
    data: RawData
  ): Promise<void> {
    const message = rawDataToString(data).trim();
    if (!message) {
      return;
    }

    if (message === "ping" && socket.readyState === WebSocket.OPEN) {
      socket.send("pong");
      return;
    }

    if (!this.requestHandler) {
      return;
    }

    try {
      const request = JSON.parse(message) as DaemonRequest;
      const response = await this.requestHandler(clientId, request);
      this.clientRegistry.sendToClient(clientId, response);
    } catch (error) {
      this.clientRegistry.sendToClient(clientId, {
        id: "unknown",
        ok: false,
        error: `Failed to parse request: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  }

  private writeJson(
    response: ServerResponse,
    statusCode: number,
    body: Record<string, unknown> | DaemonResponse | RemoteControlStatus
  ): void {
    response.statusCode = statusCode;
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Cache-Control", JSON_CACHE_CONTROL);
    response.end(JSON.stringify(body));
  }
}
