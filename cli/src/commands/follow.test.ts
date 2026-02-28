import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { startAppHistoryStream } from "./follow.js";

function historyLine(input: {
  sessionID: string;
  text: string;
  type: string;
}): string {
  return `${JSON.stringify(input)}\n`;
}

describe("startAppHistoryStream", () => {
  let tempDir = "";

  beforeEach(() => {
    vi.useFakeTimers();
    tempDir = mkdtempSync(join(tmpdir(), "duck-follow-test-"));
  });

  afterEach(() => {
    vi.useRealTimers();
    if (tempDir) {
      rmSync(tempDir, { force: true, recursive: true });
    }
  });

  it("tails live updates from EOF by default", () => {
    const filePath = join(tempDir, "history.jsonl");
    writeFileSync(
      filePath,
      historyLine({
        sessionID: "session-a",
        text: "old",
        type: "assistant_audio",
      }),
      "utf8"
    );

    const events: string[] = [];
    const stop = startAppHistoryStream(
      filePath,
      (event) => {
        if (event.text) {
          events.push(event.text);
        }
      },
      () => {
        // Intentionally ignored for this test.
      }
    );

    vi.advanceTimersByTime(500);
    expect(events).toEqual([]);

    appendFileSync(
      filePath,
      historyLine({
        sessionID: "session-a",
        text: "new",
        type: "assistant_audio",
      }),
      "utf8"
    );
    vi.advanceTimersByTime(500);
    stop();

    expect(events).toEqual(["new"]);
  });

  it("filters events to the requested session", () => {
    const filePath = join(tempDir, "history.jsonl");
    writeFileSync(filePath, "", "utf8");

    const events: string[] = [];
    const stop = startAppHistoryStream(
      filePath,
      (event) => {
        if (event.text) {
          events.push(event.text);
        }
      },
      () => {
        // Intentionally ignored for this test.
      },
      {
        sessionId: "session-target",
        startFromEnd: false,
      }
    );

    appendFileSync(
      filePath,
      historyLine({
        sessionID: "session-other",
        text: "ignore-me",
        type: "assistant_audio",
      }),
      "utf8"
    );
    appendFileSync(
      filePath,
      historyLine({
        sessionID: "session-target",
        text: "keep-me",
        type: "assistant_audio",
      }),
      "utf8"
    );

    vi.advanceTimersByTime(500);
    stop();

    expect(events).toEqual(["keep-me"]);
  });

  it("captures first events when file appears after follow starts and startFromEnd is false", () => {
    const filePath = join(tempDir, "history-late.jsonl");
    const events: string[] = [];

    const stop = startAppHistoryStream(
      filePath,
      (event) => {
        if (event.text) {
          events.push(event.text);
        }
      },
      () => {
        // Intentionally ignored for this test.
      },
      {
        startFromEnd: false,
      }
    );

    vi.advanceTimersByTime(500);
    expect(events).toEqual([]);

    writeFileSync(
      filePath,
      historyLine({
        sessionID: "session-a",
        text: "first-line",
        type: "assistant_audio",
      }),
      "utf8"
    );

    vi.advanceTimersByTime(500);
    stop();

    expect(events).toEqual(["first-line"]);
  });
});
