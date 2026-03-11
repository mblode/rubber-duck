export function createDaemonSidebandClient() {
  const listeners = new Set();
  const state = {
    callId: null,
    lastError: null,
    sessionId: null,
    status: "idle",
  };

  return {
    async connect(options = {}) {
      updateState({
        callId: options.callId ?? state.callId,
        lastError: null,
        sessionId: options.sessionId ?? state.sessionId,
        status: "connecting",
      });

      const config =
        options.config ?? globalThis.__RUBBER_DUCK_REMOTE_CONFIG__?.sideband;
      await Promise.resolve();

      if (!config?.url) {
        updateState({ status: "awaiting_backend" });
        return { ok: false, reason: "awaiting_backend" };
      }

      updateState({
        callId: config.callId ?? options.callId ?? state.callId,
        status: "ready_for_socket",
      });
      emit({
        callId: state.callId,
        sessionId: state.sessionId,
        type: "follow_requested",
      });
      return { ok: true, status: state.status };
    },
    disconnect() {
      updateState({
        callId: null,
        lastError: null,
        sessionId: null,
        status: "idle",
      });
      emit({ type: "disconnected" });
    },
    followSession(sessionId) {
      updateState({ sessionId });
      emit({ sessionId, type: "follow_requested" });
    },
    getSnapshot() {
      return { ...state };
    },
    ingestServerEvent(event) {
      emit({ event, type: "server_event" });
    },
    on(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    sendCommand(event, payload = {}) {
      const envelope = {
        callId: state.callId,
        event,
        payload,
        sessionId: state.sessionId,
      };
      emit({ envelope, type: "daemon_command" });
      return envelope;
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
