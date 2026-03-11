export function createInitialState() {
  return {
    screen: "pairing",
    pairing: {
      authState: "signed_out",
      deviceName: "Worker 2 iPhone",
      lastPairedAt: null,
      paired: false,
      pairCode: "",
      provider: "openai",
      resumeAvailable: true,
    },
    runtime: {
      callId: null,
      muted: false,
      replaying: false,
      sidebandStatus: "idle",
      voiceState: "idle",
      webRtcStatus: "idle",
    },
    session: {
      assistantSummary:
        "Remote shell snapshot is ready. Transcript rendering and tool rail are hydrated from the latest session preview.",
      lastActiveAt: "2 minutes ago",
      model: "gpt-realtime",
      sessionId: "sess_remote_duck_01",
      sessionName: "duck-voice-shell",
      statusLabel: "Resume available",
      workspacePath: "/Users/mblode/Code/mblode/rubber-duck",
    },
    transcript: [
      {
        id: "msg-1",
        role: "system",
        summary: "Warm resume",
        text: "Continue the current repo session or pair a fresh device. The remote shell will keep transcript and tool state separate from live transport setup.",
        timestamp: "Now",
      },
      {
        id: "msg-2",
        role: "user",
        summary: "Current focus",
        text: "Build the iPhone-first PWA shell in cli/src/web-client and keep daemon integration as a future adapter boundary.",
        timestamp: "1 minute ago",
      },
      {
        id: "msg-3",
        role: "assistant",
        summary: "Progress",
        text: "I mapped the daemon event shapes and started a client architecture with a static shell, a transcript lane, and a tool rail ready for sideband updates.",
        timestamp: "1 minute ago",
      },
    ],
    tools: [
      {
        args: '{ path: "cli/src/types.ts" }',
        durationLabel: "64ms",
        id: "tool-1",
        name: "read_file",
        outputPreview:
          "Loaded daemon method and Pi event types so the remote shell can mirror real session names.",
        status: "done",
      },
      {
        args: '{ query: "voice_state" }',
        durationLabel: "118ms",
        id: "tool-2",
        name: "grep_search",
        outputPreview:
          "Found voice_state lifecycle in cli/src/daemon/request-handler.ts and confirmed follow/session payloads.",
        status: "done",
      },
      {
        args: '{ command: "connect sideband" }',
        durationLabel: "pending bridge",
        id: "tool-3",
        name: "daemon_sideband",
        outputPreview:
          "Awaiting remote bridge URL. Client adapter is scaffolded and can follow a call_id when the backend exists.",
        status: "queued",
      },
    ],
    toast: null,
  };
}

export function mergeSavedState(baseState, savedState) {
  if (!savedState || typeof savedState !== "object") {
    return baseState;
  }

  return {
    ...baseState,
    screen: savedState.screen ?? baseState.screen,
    pairing: {
      ...baseState.pairing,
      ...(savedState.pairing ?? {}),
    },
    runtime: {
      ...baseState.runtime,
      ...(savedState.runtime ?? {}),
    },
    session: {
      ...baseState.session,
      ...(savedState.session ?? {}),
    },
    transcript:
      Array.isArray(savedState.transcript) && savedState.transcript.length > 0
        ? savedState.transcript
        : baseState.transcript,
    tools:
      Array.isArray(savedState.tools) && savedState.tools.length > 0
        ? savedState.tools
        : baseState.tools,
    toast: null,
  };
}
