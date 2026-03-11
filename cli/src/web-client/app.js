import { createInitialState, mergeSavedState } from "./data/demo-state.js";
import { createDaemonSidebandClient } from "./runtime/daemon-sideband-client.js";
import { createOpenAIRealtimeClient } from "./runtime/openai-realtime-client.js";
import { createRemoteShellController } from "./runtime/remote-shell-controller.js";
import { reducer } from "./state/reducer.js";
import { createStore } from "./state/store.js";
import { renderApp } from "./ui/render-app.js";

const STORAGE_KEY = "rubber-duck-remote-shell/v1";

const appRoot = document.querySelector("#app");
if (!appRoot) {
  throw new Error("Missing #app mount node");
}

const store = createStore(
  reducer,
  mergeSavedState(createInitialState(), readSavedState())
);

const realtimeClient = createOpenAIRealtimeClient();
const sidebandClient = createDaemonSidebandClient();

const controller = createRemoteShellController({
  store,
  realtimeClient,
  sidebandClient,
  setRoute,
});

store.subscribe((state) => {
  appRoot.innerHTML = renderApp(state);
  writeSavedState(state);
});

appRoot.innerHTML = renderApp(store.getState());

document.addEventListener("click", (event) => {
  const target = event.target instanceof Element ? event.target : null;
  const actionNode = target?.closest("[data-action]");
  if (!actionNode) {
    return;
  }

  const { action, provider } = actionNode.dataset;
  switch (action) {
    case "open-pairing":
      controller.openPairing();
      break;
    case "open-session":
      controller.openSession();
      break;
    case "select-provider":
      controller.selectProvider(provider ?? "openai");
      break;
    case "pair-device":
      controller.pairDevice(readPairingForm());
      break;
    case "continue-guest":
      controller.continueAsGuest(readPairingForm());
      break;
    case "reconnect-runtime":
      controller.connectRuntime();
      break;
    case "replay-activity":
      controller.replayActivity();
      break;
    case "toggle-mute":
      controller.toggleMute();
      break;
    case "clear-toast":
      controller.clearToast();
      break;
    default:
      break;
  }
});

window.addEventListener("hashchange", () => {
  controller.syncRoute(window.location.hash);
});

controller.bootstrap(window.location.hash);
registerServiceWorker();

function readPairingForm() {
  const pairCodeInput = document.querySelector("[data-pair-code]");
  const deviceNameInput = document.querySelector("[data-device-name]");

  const pairCode =
    pairCodeInput instanceof HTMLInputElement ? pairCodeInput.value : "";
  const deviceName =
    deviceNameInput instanceof HTMLInputElement ? deviceNameInput.value : "";

  return { pairCode, deviceName };
}

function setRoute(screen) {
  const nextHash = screen === "session" ? "#/session" : "#/pairing";
  if (window.location.hash !== nextHash) {
    window.location.hash = nextHash;
  }
}

function readSavedState() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return null;
    }
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeSavedState(state) {
  const payload = {
    screen: state.screen,
    pairing: {
      authState: state.pairing.authState,
      deviceName: state.pairing.deviceName,
      lastPairedAt: state.pairing.lastPairedAt,
      paired: state.pairing.paired,
      provider: state.pairing.provider,
    },
    runtime: {
      callId: state.runtime.callId,
      muted: state.runtime.muted,
      sidebandStatus: state.runtime.sidebandStatus,
      voiceState: state.runtime.voiceState,
      webRtcStatus: state.runtime.webRtcStatus,
    },
    session: state.session,
    tools: state.tools,
    transcript: state.transcript,
  };

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
  } catch {
    // Best-effort persistence only.
  }
}

function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) {
    return;
  }

  window.addEventListener("load", async () => {
    try {
      await navigator.serviceWorker.register("./sw.js");
    } catch {
      // Ignore service worker failures in local preview environments.
    }
  });
}
