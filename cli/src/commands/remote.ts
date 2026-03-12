import { hostname } from "node:os";
import { styleText } from "node:util";
import { log } from "@clack/prompts";
import type { Command } from "commander";
import { DaemonClient } from "../client.js";
import { DEFAULT_REMOTE_PORT } from "../constants.js";
import { ensureDaemon } from "../ensure-daemon.js";
import type { RemoteConfigureParams, RemoteControlStatus } from "../types.js";

interface RemoteConfigureResult {
  authToken?: string | null;
  status: RemoteControlStatus;
}

const URL_SCHEME_PATTERN = /^[a-z][a-z\d+\-.]*:\/\//i;

function parsePort(value: string): number {
  const port = Number.parseInt(value, 10);
  if (!Number.isInteger(port) || port < 0 || port > 65_535) {
    throw new Error(`Invalid port: ${value}`);
  }
  return port;
}

function renderStatus(status: RemoteControlStatus): void {
  let state = styleText("dim", "disabled");
  if (status.listening) {
    state = styleText("green", "listening");
  } else if (status.enabled) {
    state = styleText("yellow", "configured");
  }

  console.log(`${styleText("bold", "State")}        ${state}`);
  console.log(`${styleText("bold", "Host")}         ${status.host}`);
  console.log(`${styleText("bold", "Port")}         ${status.port}`);
  console.log(
    `${styleText("bold", "Transport")}    ${status.tlsEnabled ? "https + wss" : "http + ws"}`
  );
  console.log(
    `${styleText("bold", "Auth Token")}   ${status.tokenConfigured ? "configured" : "missing"}`
  );
  console.log(
    `${styleText("bold", "HTTP URL")}     ${status.httpUrl ?? styleText("dim", "not listening")}`
  );
  console.log(
    `${styleText("bold", "WebSocket")}    ${status.wsUrl ?? styleText("dim", "not listening")}`
  );
  console.log(
    `${styleText("bold", "Clients")}      ${status.connectedClients}`
  );
  console.log(
    `${styleText("bold", "Token Updated")} ${status.tokenUpdatedAt ?? styleText("dim", "never")}`
  );

  if (status.lastError) {
    console.log(`${styleText("bold", "Last Error")}   ${status.lastError}`);
  }
}

async function withDaemon<T>(
  action: (client: DaemonClient) => Promise<T>
): Promise<T> {
  await ensureDaemon();
  const client = await DaemonClient.connect();

  try {
    return await action(client);
  } finally {
    client.close();
  }
}

function fetchStatus(includeToken = false): Promise<RemoteConfigureResult> {
  return withDaemon(async (client) => {
    const response = await client.request(
      "remote_status",
      includeToken ? { includeToken: true } : {}
    );
    if (!(response.ok && response.data)) {
      throw new Error(response.error ?? "Failed to fetch remote status");
    }

    return response.data as unknown as RemoteConfigureResult;
  });
}

function configureRemote(
  params: RemoteConfigureParams
): Promise<RemoteConfigureResult> {
  return withDaemon(async (client) => {
    const response = await client.request("remote_configure", params);
    if (!(response.ok && response.data)) {
      throw new Error(response.error ?? "Failed to configure remote control");
    }

    return response.data as unknown as RemoteConfigureResult;
  });
}

function printToken(token: string | null | undefined): void {
  if (!token) {
    return;
  }

  console.log("");
  console.log(styleText("bold", "Auth token"));
  console.log(token);
}

function warnIfInsecureExposure(status: RemoteControlStatus): void {
  const isNonLoopbackHost =
    status.host !== "127.0.0.1" &&
    status.host !== "localhost" &&
    status.host !== "::1";

  if (isNonLoopbackHost && !status.tlsEnabled) {
    log.warn(
      "Remote control is exposed without TLS. Prefer localhost or configure cert/key paths before binding publicly."
    );
  }
}

function isLoopbackHost(host: string): boolean {
  const normalized = host.trim().toLowerCase();
  return (
    normalized === "127.0.0.1" ||
    normalized === "localhost" ||
    normalized === "::1"
  );
}

export function normalizePublicUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error(`Invalid public URL: ${value}`);
  }

  const hasExplicitScheme = URL_SCHEME_PATTERN.test(trimmed);
  const normalizedInput = hasExplicitScheme
    ? trimmed
    : `${trimmed.toLowerCase().includes(".ts.net") ? "https" : "http"}://${trimmed}`;

  let url: URL;

  try {
    url = new URL(normalizedInput);
  } catch {
    throw new Error(`Invalid public URL: ${value}`);
  }

  const hasSupportedProtocol =
    url.protocol === "https:" || url.protocol === "http:";
  if (!(hasSupportedProtocol && url.host)) {
    throw new Error(`Invalid public URL: ${value}`);
  }

  if (url.protocol === "http:" && !url.port) {
    url.port = String(DEFAULT_REMOTE_PORT);
  }

  url.pathname = "";
  url.search = "";
  url.hash = "";
  const normalized = url.toString();
  return normalized.endsWith("/") ? normalized.slice(0, -1) : normalized;
}

function inferPublicUrl(status: RemoteControlStatus): string | null {
  if (!status.httpUrl) {
    return null;
  }

  const url = new URL(status.httpUrl);
  if (isLoopbackHost(url.hostname)) {
    return null;
  }

  return `${url.protocol}//${url.host}`;
}

function buildPairLink(publicUrl: string, authToken: string): string {
  const pairUrl = new URL("rubberduck://pair");
  pairUrl.searchParams.set("host", publicUrl);
  pairUrl.searchParams.set("token", authToken);
  pairUrl.searchParams.set("displayName", hostname());
  return pairUrl.toString();
}

async function preparePairing(options: {
  publicUrl?: string;
  rotateToken?: boolean;
}): Promise<RemoteConfigureResult & { publicUrl?: string; pairLink?: string }> {
  let snapshot = await fetchStatus(true);
  const requestedRotate = options.rotateToken ?? false;
  const needsEnable = !(
    snapshot.status.enabled &&
    snapshot.status.listening &&
    snapshot.authToken
  );

  if (needsEnable || requestedRotate) {
    snapshot = await configureRemote({
      enabled: true,
      includeToken: true,
      rotateToken: requestedRotate || !snapshot.authToken,
    });
  }

  if (!snapshot.authToken) {
    snapshot = await fetchStatus(true);
  }

  if (!snapshot.authToken) {
    throw new Error("Remote auth token is unavailable");
  }

  const publicUrl = options.publicUrl
    ? normalizePublicUrl(options.publicUrl)
    : (inferPublicUrl(snapshot.status) ?? undefined);

  return {
    ...snapshot,
    publicUrl,
    pairLink: publicUrl
      ? buildPairLink(publicUrl, snapshot.authToken)
      : undefined,
  };
}

export function registerRemoteCommand(program: Command): void {
  const remote = program
    .command("remote")
    .description("Manage the daemon's remote control plane");

  remote
    .command("status")
    .description("Show remote control status")
    .option("--json", "Output status as JSON")
    .action(async (options) => {
      try {
        const { status } = await fetchStatus();

        if (options.json) {
          console.log(JSON.stringify(status, null, 2));
          return;
        }

        renderStatus(status);
      } catch (error) {
        log.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  remote
    .command("enable")
    .description("Enable the remote control plane")
    .option("--host <host>", "Bind host")
    .option("--port <port>", "Bind port", parsePort)
    .option("--tls-cert <path>", "Path to TLS certificate PEM")
    .option("--tls-key <path>", "Path to TLS private key PEM")
    .option("--token <token>", "Set an explicit auth token")
    .option("--rotate-token", "Rotate the auth token")
    .option("--json", "Output status as JSON")
    .action(async (options) => {
      try {
        const result = await configureRemote({
          enabled: true,
          host: options.host,
          port: options.port,
          tlsCertPath: options.tlsCert,
          tlsKeyPath: options.tlsKey,
          authToken: options.token,
          rotateToken: options.rotateToken ?? false,
          includeToken: true,
        });

        if (options.json) {
          console.log(JSON.stringify(result, null, 2));
          return;
        }

        renderStatus(result.status);
        printToken(result.authToken);
        warnIfInsecureExposure(result.status);
      } catch (error) {
        log.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  remote
    .command("disable")
    .description("Disable the remote control plane")
    .option("--json", "Output status as JSON")
    .action(async (options) => {
      try {
        const result = await configureRemote({
          enabled: false,
          includeToken: false,
        });

        if (options.json) {
          console.log(JSON.stringify(result, null, 2));
          return;
        }

        renderStatus(result.status);
      } catch (error) {
        log.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  remote
    .command("pair")
    .description("Prepare a local pairing link for the iPhone app")
    .option(
      "--public-url <url>",
      "Public URL, hostname, or IP address the phone can reach"
    )
    .option("--rotate-token", "Rotate the auth token before pairing")
    .option("--json", "Output pairing data as JSON")
    .action(async (options) => {
      try {
        const result = await preparePairing({
          publicUrl: options.publicUrl,
          rotateToken: options.rotateToken ?? false,
        });

        if (options.json) {
          console.log(JSON.stringify(result, null, 2));
          return;
        }

        renderStatus(result.status);
        printToken(result.authToken);

        if (result.publicUrl) {
          console.log("");
          console.log(
            `${styleText("bold", "Public URL")}   ${result.publicUrl}`
          );
        }

        if (result.pairLink) {
          console.log(
            `${styleText("bold", "Pair Link")}    ${result.pairLink}`
          );
        } else {
          log.warn(
            "No public URL available for pairing. Pass --public-url or use the macOS Settings QR flow."
          );
        }

        warnIfInsecureExposure(result.status);
      } catch (error) {
        log.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  remote
    .command("token")
    .description("Show, rotate, or set the remote auth token")
    .option("--value <token>", "Set an explicit auth token value")
    .option("--rotate", "Rotate the auth token")
    .option("--json", "Output status as JSON")
    .action(async (options) => {
      try {
        const result =
          options.value || options.rotate
            ? await configureRemote({
                authToken: options.value,
                rotateToken: options.rotate ?? false,
                includeToken: true,
              })
            : await fetchStatus(true);

        if (options.json) {
          console.log(JSON.stringify(result, null, 2));
          return;
        }

        renderStatus(result.status);
        printToken(result.authToken);
      } catch (error) {
        log.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  remote.action(async () => {
    try {
      const { status } = await fetchStatus();
      renderStatus(status);
    } catch (error) {
      log.error(error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });
}
