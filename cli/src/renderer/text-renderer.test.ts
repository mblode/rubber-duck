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

  it("renders app history user_text with prompt marker", () => {
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

    expect(output).toContain("> Hey there");
  });

  it("renders app history assistant final text", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const event: RendererPiEvent = {
      appEventType: "assistant_text",
      text: "How can I help?",
      type: "app_history_event",
    };
    renderer.render(event);
    renderer.cleanup();

    expect(output).toContain("How can I help?");
  });

  it("ignores Pi text deltas in non-streaming mode", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      assistantMessageEvent: { delta: "Hello from delta", type: "text_delta" },
      message: { role: "assistant" },
      type: "message_update",
    });
    renderer.cleanup();

    expect(output).toBe("");
  });

  it("renders assistant output from message_end final message", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      type: "message_end",
      message: { role: "assistant", content: "Final answer" },
    });
    renderer.cleanup();

    expect(output).toContain("Final answer");
  });

  it("deduplicates equivalent turn_end and message_end assistant output", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      type: "turn_end",
      message: { role: "assistant", content: "Same answer" },
      toolResults: [],
    });
    renderer.render({
      type: "message_end",
      message: { role: "assistant", content: "Same answer" },
    });
    renderer.cleanup();

    const occurrences = output.split("Same answer").length - 1;
    expect(occurrences).toBe(1);
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

  it("ignores app history assistant delta events in non-streaming mode", () => {
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
      appEventType: "assistant_text_end",
      type: "app_history_event",
    });
    renderer.cleanup();

    expect(output).toBe("");
  });

  it("deduplicates final assistant_audio after assistant_text", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      appEventType: "assistant_text",
      text: "Hi there",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_audio",
      text: "Hi there",
      type: "app_history_event",
    });
    renderer.cleanup();

    const occurrences = output.split("Hi there").length - 1;
    expect(occurrences).toBe(1);
  });

  it("deduplicates app history final text against recent Pi final output", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      type: "message_end",
      message: { role: "assistant", content: "Hello there" },
    });
    renderer.render({
      appEventType: "assistant_audio",
      text: "Hello there",
      type: "app_history_event",
    });
    renderer.cleanup();

    const occurrences = output.split("Hello there").length - 1;
    expect(occurrences).toBe(1);
  });

  it("does not deduplicate distinct final text variants", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    renderer.render({
      appEventType: "assistant_text",
      text: "Hi there",
      type: "app_history_event",
    });
    renderer.render({
      appEventType: "assistant_audio",
      text: "Hi there!",
      type: "app_history_event",
    });
    renderer.cleanup();

    expect(output).toContain("Hi there");
    expect(output).toContain("Hi there!");
  });

  it("renders thinking output when enabled", () => {
    const renderer = createTextRenderer({
      color: false,
      json: false,
      showThinking: true,
      verbose: false,
    });

    renderer.render({
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "thinking_start" },
    });
    renderer.render({
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "thinking_delta", delta: "..." },
    });
    renderer.render({
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "thinking_end" },
    });
    renderer.cleanup();

    expect(output).toContain("...");
  });
});
