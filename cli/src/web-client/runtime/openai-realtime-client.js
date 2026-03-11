export function createOpenAIRealtimeClient() {
  const listeners = new Set();
  const state = {
    callId: null,
    lastError: null,
    muted: false,
    status: "idle",
  };

  return {
    bindCallId(callId) {
      updateState({ callId });
    },
    async connect(options = {}) {
      updateState({ lastError: null, status: "connecting" });

      const config =
        options.config ?? globalThis.__RUBBER_DUCK_REMOTE_CONFIG__?.realtime;
      await Promise.resolve();

      if (!globalThis.RTCPeerConnection) {
        updateState({
          lastError: "WebRTC is unavailable in this browser.",
          status: "unsupported",
        });
        return { ok: false, reason: "unsupported" };
      }

      if (!(config?.sdpEndpoint || config?.ephemeralKeyEndpoint)) {
        updateState({ status: "awaiting_backend" });
        emit({
          type: "needs_session_bootstrap",
          session: options.session ?? null,
        });
        return { ok: false, reason: "awaiting_backend" };
      }

      updateState({
        callId: config.callId ?? options.callId ?? state.callId,
        status: "ready_for_offer",
      });
      emit({
        type: "needs_session_bootstrap",
        session: options.session ?? null,
      });
      return {
        callId: state.callId,
        ok: true,
        status: state.status,
      };
    },
    disconnect() {
      updateState({
        callId: null,
        lastError: null,
        status: "idle",
      });
      emit({ type: "disconnected" });
    },
    getSnapshot() {
      return { ...state };
    },
    mute(nextMuted) {
      updateState({ muted: Boolean(nextMuted) });
      emit({ muted: state.muted, type: "mute" });
      return state.muted;
    },
    on(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    sendClientEvent(event) {
      emit({ event, type: "client_event" });
      return event;
    },
    updateSession(session) {
      const event = {
        session,
        type: "session.update",
      };
      emit({ event, type: "client_event" });
      return event;
    },
  };

  function updateState(patch) {
    Object.assign(state, patch);
    emit({ snapshot: { ...state }, type: "status" });
  }

  function emit(event) {
    for (const listener of listeners) {
      listener(event);
    }
  }
}
