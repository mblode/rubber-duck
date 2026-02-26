import type { AgentMessage } from "./types.js";

const MAX_ARG_VALUE_LENGTH = 120;

export function formatTag(name: string): string {
  return `[${name}]`;
}

export function formatToolArgs(args: Record<string, unknown>): string {
  return Object.entries(args)
    .map(([key, value]) => {
      const str = typeof value === "string" ? value : JSON.stringify(value);
      const truncated =
        str.length > MAX_ARG_VALUE_LENGTH
          ? `${str.slice(0, MAX_ARG_VALUE_LENGTH)}...`
          : str;
      return `${key}=${JSON.stringify(truncated)}`;
    })
    .join(" ");
}

export function formatUserMessage(message: AgentMessage): string {
  if (typeof message.content === "string") {
    return message.content;
  }
  if (Array.isArray(message.content)) {
    return message.content
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join("\n");
  }
  return "";
}

export function truncate(str: string, maxLen: number): string {
  if (str.length <= maxLen) {
    return str;
  }
  return `${str.slice(0, maxLen)}...`;
}
