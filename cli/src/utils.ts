import { createHash, randomUUID } from "node:crypto";
import { statSync } from "node:fs";
import { homedir } from "node:os";
import { parse, resolve } from "node:path";

export function generateId(): string {
  return randomUUID();
}

export function workspaceId(absolutePath: string): string {
  return createHash("sha256").update(absolutePath).digest("hex").slice(0, 12);
}

export function resolveWorkspacePath(pathArg?: string): string {
  const inputPath = pathArg ?? process.cwd();
  if (inputPath === "~") {
    return homedir();
  }
  if (inputPath.startsWith("~/")) {
    return resolve(homedir(), inputPath.slice(2));
  }
  return resolve(inputPath);
}

export function formatTimestamp(iso: string): string {
  const date = new Date(iso);
  const now = Date.now();
  const diffMs = now - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);

  if (diffSec < 60) {
    return "just now";
  }
  if (diffMin < 60) {
    return `${diffMin}m ago`;
  }
  if (diffHr < 24) {
    return `${diffHr}h ago`;
  }
  if (diffDay < 30) {
    return `${diffDay}d ago`;
  }
  return date.toLocaleDateString();
}

export function findGitRoot(startPath: string): string | null {
  let current = resolve(startPath);
  const { root } = parse(current);
  while (current !== root) {
    try {
      statSync(resolve(current, ".git"));
      return current;
    } catch {
      current = resolve(current, "..");
    }
  }
  return null;
}
