export function reducer(state, action) {
  switch (action.type) {
    case "set_screen":
      return {
        ...state,
        screen: action.payload,
      };

    case "set_provider":
      return {
        ...state,
        pairing: {
          ...state.pairing,
          provider: action.payload,
        },
      };

    case "complete_pairing":
      return {
        ...state,
        screen: "session",
        pairing: {
          ...state.pairing,
          authState: action.payload.authState,
          deviceName: action.payload.deviceName,
          lastPairedAt: action.payload.lastPairedAt,
          paired: true,
          pairCode: action.payload.pairCode,
          provider: action.payload.provider,
        },
        session: {
          ...state.session,
          lastActiveAt: "Just now",
          statusLabel: "Connected shell ready",
        },
      };

    case "set_runtime_status":
      return {
        ...state,
        runtime: {
          ...state.runtime,
          [action.payload.key]: action.payload.value,
        },
      };

    case "set_call_id":
      return {
        ...state,
        runtime: {
          ...state.runtime,
          callId: action.payload,
        },
      };

    case "set_voice_state":
      return {
        ...state,
        runtime: {
          ...state.runtime,
          voiceState: action.payload,
        },
      };

    case "toggle_mute":
      return {
        ...state,
        runtime: {
          ...state.runtime,
          muted:
            typeof action.payload === "boolean"
              ? action.payload
              : !state.runtime.muted,
        },
      };

    case "set_toast":
      return {
        ...state,
        toast: action.payload,
      };

    case "clear_toast":
      return {
        ...state,
        toast: null,
      };

    case "set_replay_state":
      return {
        ...state,
        runtime: {
          ...state.runtime,
          replaying: action.payload,
        },
      };

    case "append_transcript":
      return {
        ...state,
        transcript: [...state.transcript, action.payload],
      };

    case "append_tool":
      return {
        ...state,
        tools: [action.payload, ...state.tools],
      };

    case "update_tool":
      return {
        ...state,
        tools: state.tools.map((tool) =>
          tool.id === action.payload.id
            ? {
                ...tool,
                ...action.payload.patch,
              }
            : tool
        ),
      };

    case "update_session_meta":
      return {
        ...state,
        session: {
          ...state.session,
          ...action.payload,
        },
      };

    default:
      return state;
  }
}
