import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { DaemonEvent } from "../types.js";

const mocks = vi.hoisted(() => ({
  clearLineMock: vi.fn(),
  cursorToMock: vi.fn(),
  rendererRenderMock: vi.fn(),
  rlCloseMock: vi.fn(),
  rlOnMock: vi.fn(),
  rlPauseMock: vi.fn(),
  rlPromptMock: vi.fn(),
  rlResumeMock: vi.fn(),
}));

vi.mock("node:readline", () => ({
  clearLine: mocks.clearLineMock,
  createInterface: vi.fn(() => ({
    close: mocks.rlCloseMock,
    line: "",
    on: mocks.rlOnMock,
    pause: mocks.rlPauseMock,
    prompt: mocks.rlPromptMock,
    resume: mocks.rlResumeMock,
  })),
  cursorTo: mocks.cursorToMock,
}));

vi.mock("../renderer/index.js", () => ({
  createRenderer: vi.fn(() => ({
    cleanup: vi.fn(),
    isStreaming: () => false,
    render: mocks.rendererRenderMock,
  })),
}));

vi.mock("./stream-lifecycle.js", () => ({
  createStreamLifecycle: vi.fn(() => ({
    cleanup: vi.fn(),
  })),
}));

vi.mock("./ui-response.js", () => ({
  handleUiEvent: vi.fn(),
}));

vi.mock("@clack/prompts", () => ({
  log: {
    error: vi.fn(),
    info: vi.fn(),
    step: vi.fn(),
    warn: vi.fn(),
  },
}));

import { startFollowStream } from "./follow.js";

interface FakeClient {
  onEvent: (handler: (event: DaemonEvent) => void) => void;
  request: (
    method: string,
    params: Record<string, unknown>
  ) => Promise<{
    ok: boolean;
    data?: Record<string, unknown>;
    error?: string;
  }>;
}

function createFakeClient(onEventRef: {
  current: ((event: DaemonEvent) => void) | null;
}): FakeClient {
  return {
    onEvent(handler) {
      onEventRef.current = handler;
    },
    request(method) {
      if (method !== "follow") {
        return Promise.resolve({ ok: true, data: {} });
      }
      return Promise.resolve({
        ok: true,
        data: {
          sessionName: "duck-1",
          workspacePath: "/tmp/workspace",
          sessionId: "session-1",
          isRunning: true,
          appHistoryFile: undefined,
          appHistoryExists: false,
          appHistorySizeBytes: 0,
        },
      });
    },
  };
}

describe("startFollowStream interactive prompt handling", () => {
  const stdinTty = Object.getOwnPropertyDescriptor(process.stdin, "isTTY");
  const stdoutTty = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");

  beforeEach(() => {
    vi.useFakeTimers();
    mocks.clearLineMock.mockClear();
    mocks.cursorToMock.mockClear();
    mocks.rlPromptMock.mockClear();
    mocks.rlPauseMock.mockClear();
    mocks.rlResumeMock.mockClear();
    mocks.rlCloseMock.mockClear();
    mocks.rlOnMock.mockClear();
    mocks.rendererRenderMock.mockReset();
    Object.defineProperty(process.stdin, "isTTY", {
      configurable: true,
      value: true,
    });
    Object.defineProperty(process.stdout, "isTTY", {
      configurable: true,
      value: true,
    });
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    if (stdinTty) {
      Object.defineProperty(process.stdin, "isTTY", stdinTty);
    }
    if (stdoutTty) {
      Object.defineProperty(process.stdout, "isTTY", stdoutTty);
    }
  });

  it("keeps input active across non-streaming turn events", async () => {
    const onEventRef: { current: ((event: DaemonEvent) => void) | null } = {
      current: null,
    };
    const client = createFakeClient(onEventRef);

    await startFollowStream(client as never, undefined, {
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    expect(mocks.rlPromptMock).toHaveBeenCalledTimes(1);
    const onEvent = onEventRef.current;
    expect(onEvent).not.toBeNull();

    onEvent?.({
      event: "turn_start",
      sessionId: "session-1",
      data: {
        type: "turn_start",
      },
    } as DaemonEvent);

    onEvent?.({
      event: "turn_end",
      sessionId: "session-1",
      data: {
        type: "turn_end",
        message: { role: "assistant", content: "done" },
        toolResults: [],
      },
    } as DaemonEvent);

    expect(mocks.rlPauseMock).not.toHaveBeenCalled();
    expect(mocks.rlResumeMock).not.toHaveBeenCalled();
    expect(mocks.rlPromptMock).toHaveBeenCalledWith(true);
    expect(mocks.cursorToMock).toHaveBeenCalledTimes(2);
    expect(mocks.clearLineMock).toHaveBeenCalledTimes(2);
  });

  it("preserves prompt around non-streaming daemon events", async () => {
    const onEventRef: { current: ((event: DaemonEvent) => void) | null } = {
      current: null,
    };
    const client = createFakeClient(onEventRef);

    await startFollowStream(client as never, undefined, {
      color: false,
      json: false,
      showThinking: false,
      verbose: false,
    });

    const onEvent = onEventRef.current;
    expect(onEvent).not.toBeNull();

    onEvent?.({
      event: "tool_execution_start",
      sessionId: "session-1",
      data: {
        type: "tool_execution_start",
        toolCallId: "tc_1",
        toolName: "bash",
        args: { command: "ls" },
      },
    } as DaemonEvent);

    expect(mocks.cursorToMock).toHaveBeenCalledTimes(1);
    expect(mocks.clearLineMock).toHaveBeenCalledTimes(1);
    expect(mocks.rlPauseMock).not.toHaveBeenCalled();
    expect(mocks.rlPromptMock).toHaveBeenCalledWith(true);
  });
});
