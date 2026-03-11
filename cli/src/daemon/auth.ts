import { randomBytes, timingSafeEqual } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { REMOTE_AUTH_TOKEN_PATH } from "../constants.js";

function generateAuthToken(): string {
  return randomBytes(32).toString("hex");
}

export function loadRemoteAuthToken(): string | null {
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

export function ensureRemoteAuthToken(options?: {
  regenerate?: boolean;
}): string {
  const regenerate = options?.regenerate ?? false;

  if (!regenerate) {
    const existing = loadRemoteAuthToken();
    if (existing) {
      return existing;
    }
  }

  mkdirSync(dirname(REMOTE_AUTH_TOKEN_PATH), { recursive: true });
  const token = generateAuthToken();
  writeFileSync(REMOTE_AUTH_TOKEN_PATH, `${token}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  return token;
}

export function validateRemoteAuthToken(
  actualToken: string,
  expectedToken: string
): boolean {
  const actual = Buffer.from(actualToken);
  const expected = Buffer.from(expectedToken);
  if (actual.length !== expected.length) {
    return false;
  }
  return timingSafeEqual(actual, expected);
}
