import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import type { RemoteControlConfig } from "./config-store.js";

const REMOTE_AUTH_TOKEN_BYTES = 24;

function hashToken(token: string, salt: string): string {
  return scryptSync(token, salt, 32).toString("hex");
}

export function createRemoteAuthTokenRecord(token?: string): {
  hash: string;
  issuedToken: string;
  salt: string;
  updatedAt: string;
} {
  const issuedToken =
    token?.trim() || randomBytes(REMOTE_AUTH_TOKEN_BYTES).toString("base64url");
  const salt = randomBytes(16).toString("base64url");

  return {
    issuedToken,
    salt,
    hash: hashToken(issuedToken, salt),
    updatedAt: new Date().toISOString(),
  };
}

export function verifyRemoteAuthToken(
  token: string | null | undefined,
  remoteConfig: Pick<RemoteControlConfig, "authTokenHash" | "authTokenSalt">
): boolean {
  if (!(token && remoteConfig.authTokenHash && remoteConfig.authTokenSalt)) {
    return false;
  }

  const expected = Buffer.from(remoteConfig.authTokenHash, "hex");
  const actual = Buffer.from(
    hashToken(token, remoteConfig.authTokenSalt),
    "hex"
  );

  if (expected.length !== actual.length) {
    return false;
  }

  return timingSafeEqual(expected, actual);
}
