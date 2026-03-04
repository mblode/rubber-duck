import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { RendererPiEvent } from "../types.js";
import { createTextRenderer } from "./text-renderer.js";

describe("text renderer", () => {
  let output = "";
  let writeSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    output = "";
    writeSpy = vi.spyOn(process.stdout, "write").mockImplementation(((
      chunk: string | Uint8Array
    ) => {
      output += typeof chunk === "string" ? chunk : chunk.toString("utf8");
      return true;
    }) as typeof process.stdout.write);
  });

  afterEach(() => {
    writeSpy.mockRestore();
  });

  it("renders app history user_text as User label", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      appEventType: "user_text",
      text: "Hey there",
      type: "app_history_event",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toContain("User: Hey there");
  });

  it("renders app history assistant text as Duck label", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      appEventType: "assistant_audio",
      text: "How can I help?",
      type: "app_history_event",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toContain("Duck: How can I help?");
  });

  it("starts assistant text output on text_delta without text_start", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      assistantMessageEvent: { delta: "Hello from delta", type: "text_delta" },
      message: { role: "assistant" },
      type: "message_update",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toContain("Duck: Hello from delta");
  });

  it("suppresses speech_stopped user_audio marker when not verbose", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      appEventType: "user_audio",
      metadata: { state: "speech_stopped" },
      type: "app_history_event",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toBe("");
  });

  it("suppresses speech_started user_audio marker when not verbose", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      appEventType: "user_audio",
      metadata: { state: "speech_started" },
      type: "app_history_event",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toBe("");
  });

  it("streams assistant text from app history deltas", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      appEventType: "assistant_text_delta",
      text: "Hel",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_text_delta",
      text: "lo",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_text_end",
      type: "app_history_event",
    });
    renderer.cleanup();

    expect(output).toContain("Duck: Hello");
  });

  it("deduplicates final assistant_audio after streamed deltas", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      appEventType: "assistant_text_delta",
      text: "Hi there",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_text_end",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_audio",
      text: "Hi there",
      type: "app_history_event",
    });
    renderer.cleanup();

    const occurrences = output.split("Duck: Hi there").length - 1;
    expect(occurrences).toBe(1);
  });
});
