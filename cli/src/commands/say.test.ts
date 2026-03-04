import { describe, expect, it } from "vitest";
import type { AppHistoryEvent, PiEvent } from "../types.js";
import { isVisibleProgressEvent } from "./say.js";

describe("isVisibleProgressEvent", () => {
  it("ignores synthetic user message_start", () => {
    const event: PiEvent = {
      type: "message_start",
      message: { role: "user", content: "hello" },
    };
    expect(isVisibleProgressEvent(event, false)).toBe(false);
  });

  it("treats assistant text deltas as visible progress", () => {
    const event: PiEvent = {
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "text_delta", delta: "Hi" },
    };
    expect(isVisibleProgressEvent(event, false)).toBe(true);
  });

  it("only treats thinking deltas as visible when thinking is shown", () => {
    const event: PiEvent = {
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "thinking_delta", delta: "..." },
    };
    expect(isVisibleProgressEvent(event, false)).toBe(false);
    expect(isVisibleProgressEvent(event, true)).toBe(true);
  });

  it("ignores setStatus UI requests but accepts notify", () => {
    const statusEvent: PiEvent = {
      type: "extension_ui_request",
      id: "1",
      method: "setStatus",
      message: "Thinking...",
    };
    const notifyEvent: PiEvent = {
      type: "extension_ui_request",
      id: "2",
      method: "notify",
      message: "Heads up",
    };
    expect(isVisibleProgressEvent(statusEvent, false)).toBe(false);
    expect(isVisibleProgressEvent(notifyEvent, false)).toBe(true);
  });

  it("treats tool execution events as visible progress", () => {
    const event: PiEvent = {
      type: "tool_execution_start",
      toolCallId: "tc_1",
      toolName: "bash",
      args: { command: "ls" },
    };
    expect(isVisibleProgressEvent(event, false)).toBe(true);
  });

  it("treats app history assistant delta events as visible progress", () => {
    const event: AppHistoryEvent = {
      type: "app_history_event",
      appEventType: "assistant_text_delta",
      text: "hello",
    };
    expect(isVisibleProgressEvent(event, false)).toBe(true);
  });

  it("ignores app history response_complete markers for progress", () => {
    const event: AppHistoryEvent = {
      type: "app_history_event",
      appEventType: "response_complete",
    };
    expect(isVisibleProgressEvent(event, false)).toBe(false);
  });
});
