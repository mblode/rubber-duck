import { styleText } from "node:util";

type Format = Parameters<typeof styleText>[0];

function color(enabled: boolean, format: Format, value: string): string {
  if (!enabled) {
    return value;
  }
  return styleText(format, value);
}

export function defaultColorEnabled(): boolean {
  return !process.env.NO_COLOR && (process.stdout.isTTY ?? false);
}

export function createColorize(
  enabled: boolean
): (format: Parameters<typeof styleText>[0], value: string) => string {
  return (format, value) => color(enabled, format, value);
}

export function createColorStyles(enabled: boolean): {
  tag: {
    assistant: (value: string) => string;
    compact: (value: string) => string;
    error: (value: string) => string;
    output: (value: string) => string;
    retry: (value: string) => string;
    session: (value: string) => string;
    steer: (value: string) => string;
    thinking: (value: string) => string;
    tool: (value: string) => string;
    ui: (value: string) => string;
    you: (value: string) => string;
  };
  text: {
    assistant: (value: string) => string;
    dim: (value: string) => string;
    error: (value: string) => string;
    output: (value: string) => string;
    session: (value: string) => string;
    thinking: (value: string) => string;
    toolArgs: (value: string) => string;
    toolName: (value: string) => string;
    you: (value: string) => string;
  };
} {
  return {
    tag: {
      session: (value: string) => color(enabled, ["bold", "blue"], value),
      you: (value: string) => color(enabled, ["bold", "green"], value),
      assistant: (value: string) => color(enabled, ["bold", "white"], value),
      thinking: (value: string) => color(enabled, "dim", value),
      tool: (value: string) => color(enabled, ["bold", "cyan"], value),
      output: (value: string) => color(enabled, "dim", value),
      error: (value: string) => color(enabled, ["bold", "red"], value),
      steer: (value: string) => color(enabled, ["bold", "yellow"], value),
      retry: (value: string) => color(enabled, "yellow", value),
      compact: (value: string) => color(enabled, "dim", value),
      ui: (value: string) => color(enabled, ["bold", "magenta"], value),
    },
    text: {
      session: (value: string) => color(enabled, "blue", value),
      you: (value: string) => color(enabled, "green", value),
      assistant: (value: string) => value,
      thinking: (value: string) => color(enabled, "dim", value),
      toolName: (value: string) => color(enabled, "cyan", value),
      toolArgs: (value: string) => color(enabled, "dim", value),
      output: (value: string) => value,
      error: (value: string) => color(enabled, "red", value),
      dim: (value: string) => color(enabled, "dim", value),
    },
  };
}
