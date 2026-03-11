const REPLAY_DELAYS_MS = [0, 260, 720, 1120, 1460, 1720];

export function createRemoteShellController({
  store,
  realtimeClient,
  sidebandClient,
  setRoute,
}) {
  let replayTimerIds = [];
  let idCounter = 0;

  bindTransports();

  return {
    bootstrap(hash) {
      syncRoute(hash);

      const state = store.getState();
      if (state.screen === "session") {
        startConnectRuntime({ silent: true });
      }
    },
    clearToast() {
      store.dispatch({ type: "clear_toast" });
    },
    connectRuntime,
    continueAsGuest({ deviceName, pairCode }) {
      finalizePairing({
        authState: "guest",
        deviceName,
        pairCode,
        provider: "guest",
      });
    },
    openPairing() {
      store.dispatch({ payload: "pairing", type: "set_screen" });
      setRoute("pairing");
    },
    openSession() {
      store.dispatch({ payload: "session", type: "set_screen" });
      setRoute("session");
      startConnectRuntime({ silent: true });
    },
    pairDevice({ deviceName, pairCode }) {
      const cleanedPairCode = String(pairCode ?? "")
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, "")
        .slice(0, 6);

      if (cleanedPairCode.length < 4) {
        store.dispatch({
          payload:
            "Enter the pairing code shown on your Mac before continuing.",
          type: "set_toast",
        });
        return;
      }

      finalizePairing({
        authState: "signed_in",
        deviceName,
        pairCode: cleanedPairCode,
        provider: store.getState().pairing.provider,
      });
    },
    replayActivity() {
      clearReplay();
      store.dispatch({ payload: true, type: "set_replay_state" });
      store.dispatch({ payload: "thinking", type: "set_voice_state" });
      store.dispatch({
        payload: {
          statusLabel: "Streaming demo sideband activity",
        },
        type: "update_session_meta",
      });

      const steps = [
        () => {
          store.dispatch({
            payload: {
              args: '{ command: "resume current session" }',
              durationLabel: "live",
              id: "tool-replay",
              name: "follow",
              outputPreview:
                "Subscribed to the current session and restored transcript continuity.",
              status: "running",
            },
            type: "append_tool",
          });
        },
        () => {
          store.dispatch({
            payload: {
              id: nextId("assistant"),
              role: "assistant",
              summary: "Resume",
              text: "The static shell is now replaying mock session events. The transcript and tool rail stay in sync even while transport wiring is still waiting for a remote bridge.",
              timestamp: "Just now",
            },
            type: "append_transcript",
          });
        },
        () => {
          store.dispatch({
            payload: {
              args: '{ path: "cli/src/web-client" }',
              durationLabel: "91ms",
              id: nextId("tool"),
              name: "read_file",
              outputPreview:
                "Opened the remote shell modules and confirmed the adapter boundaries are isolated from the UI.",
              status: "done",
            },
            type: "append_tool",
          });
        },
        () => {
          store.dispatch({
            payload: {
              id: "tool-replay",
              patch: {
                durationLabel: "1.1s",
                status: "done",
              },
            },
            type: "update_tool",
          });
        },
        () => {
          store.dispatch({
            payload: {
              id: nextId("system"),
              role: "system",
              summary: "Bridge note",
              text: "WebRTC audio remains in placeholder mode until a backend endpoint provides an ephemeral key or SDP exchange path. Sideband follows the same pattern with a future call_id bridge.",
              timestamp: "Just now",
            },
            type: "append_transcript",
          });
        },
        () => {
          store.dispatch({ payload: false, type: "set_replay_state" });
          store.dispatch({ payload: "listening", type: "set_voice_state" });
          store.dispatch({
            payload: {
              statusLabel: "Preview refreshed",
            },
            type: "update_session_meta",
          });
          store.dispatch({
            payload: "Preview updated with mock transcript and tool events.",
            type: "set_toast",
          });
        },
      ];

      replayTimerIds = steps.map((step, index) =>
        window.setTimeout(step, REPLAY_DELAYS_MS[index])
      );
    },
    selectProvider(provider) {
      store.dispatch({ payload: provider, type: "set_provider" });
    },
    syncRoute,
    toggleMute() {
      const nextMuted = realtimeClient.mute(!store.getState().runtime.muted);
      store.dispatch({ payload: nextMuted, type: "toggle_mute" });
      store.dispatch({
        payload: nextMuted
          ? "Mic muted for remote preview."
          : "Mic live in preview mode.",
        type: "set_toast",
      });
    },
  };

  function bindTransports() {
    realtimeClient.on((event) => {
      if (event.type === "status") {
        store.dispatch({
          payload: {
            key: "webRtcStatus",
            value: event.snapshot.status,
          },
          type: "set_runtime_status",
        });
        if (event.snapshot.callId) {
          store.dispatch({
            payload: event.snapshot.callId,
            type: "set_call_id",
          });
        }
      }
    });

    sidebandClient.on((event) => {
      if (event.type === "status") {
        store.dispatch({
          payload: {
            key: "sidebandStatus",
            value: event.snapshot.status,
          },
          type: "set_runtime_status",
        });
      }

      if (
        event.type === "server_event" &&
        event.event?.type === "voice_state"
      ) {
        store.dispatch({
          payload: event.event.state ?? "idle",
          type: "set_voice_state",
        });
      }
    });
  }

  async function connectRuntime({ silent = false } = {}) {
    const state = store.getState();
    store.dispatch({
      payload: {
        key: "webRtcStatus",
        value: "connecting",
      },
      type: "set_runtime_status",
    });
    store.dispatch({
      payload: {
        key: "sidebandStatus",
        value: "connecting",
      },
      type: "set_runtime_status",
    });

    const realtimeResult = await realtimeClient.connect({
      callId: state.runtime.callId,
      session: {
        audio: {
          output: {
            voice: "marin",
          },
        },
        model: state.session.model,
        type: "realtime",
      },
    });

    const sidebandResult = await sidebandClient.connect({
      callId: realtimeClient.getSnapshot().callId,
      sessionId: state.session.sessionId,
    });

    if (realtimeResult.callId) {
      store.dispatch({ payload: realtimeResult.callId, type: "set_call_id" });
      sidebandClient.followSession(state.session.sessionId);
    }

    if (!silent) {
      store.dispatch({
        payload:
          realtimeResult.ok && sidebandResult.ok
            ? "Remote audio and sideband control are ready."
            : "Static shell is ready. Add bridge endpoints to activate live WebRTC and daemon sideband control.",
        type: "set_toast",
      });
    }
  }

  function finalizePairing({ authState, deviceName, pairCode, provider }) {
    store.dispatch({
      payload: {
        authState,
        deviceName: String(deviceName ?? "").trim() || "Remote iPhone",
        lastPairedAt: new Date().toISOString(),
        pairCode,
        provider,
      },
      type: "complete_pairing",
    });
    setRoute("session");
    startConnectRuntime();
  }

  function syncRoute(hash) {
    const isSessionRoute = hash === "#/session";
    store.dispatch({
      payload: isSessionRoute ? "session" : "pairing",
      type: "set_screen",
    });
  }

  function clearReplay() {
    for (const timerId of replayTimerIds) {
      window.clearTimeout(timerId);
    }
    replayTimerIds = [];
  }

  function startConnectRuntime(options) {
    connectRuntime(options).catch(() => {
      store.dispatch({
        payload:
          "Transport bootstrap failed. The static shell is still available.",
        type: "set_toast",
      });
    });
  }

  function nextId(prefix) {
    idCounter += 1;
    return `${prefix}-${idCounter}`;
  }
}
