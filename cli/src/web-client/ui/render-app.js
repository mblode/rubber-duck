const STATUS_VARIANTS = {
  awaiting_backend: "pill-warn",
  connecting: "pill-accent",
  done: "pill-success",
  guest: "pill-warn",
  idle: "",
  listening: "pill-live",
  paired: "pill-success",
  queued: "",
  ready_for_offer: "pill-success",
  ready_for_socket: "pill-success",
  running: "pill-live",
  signed_in: "pill-success",
  signed_out: "",
  thinking: "pill-accent",
  unsupported: "pill-danger",
};

export function renderApp(state) {
  return `
    <div class="shell">
      <div class="ambient ambient-top"></div>
      <div class="ambient ambient-bottom"></div>
      <div class="layout">
        ${renderToast(state.toast)}
        <header class="topbar">
          <div class="brandbar">
            <div class="brand">
              <div class="brand-mark">
                <img src="./assets/icon.svg" alt="" />
              </div>
              <div>
                <h1 class="brand-title">Rubber Duck Remote</h1>
                <p class="brand-copy">Pair fast. Resume the exact coding session already live on your Mac.</p>
              </div>
            </div>
            <div class="status-strip">
              ${renderPill(`auth ${state.pairing.authState}`, state.pairing.authState)}
              ${renderPill(`voice ${state.runtime.voiceState}`, state.runtime.voiceState)}
            </div>
          </div>
        </header>

        <main class="screen">
          ${
            state.screen === "pairing"
              ? renderPairingScreen(state)
              : renderSessionScreen(state)
          }
        </main>
      </div>

      ${renderBottomDock(state)}
    </div>
  `;
}

function renderPairingScreen(state) {
  return `
    <section class="panel hero-card">
      <div class="hero-grid">
        <div>
          <div class="eyebrow">Pairing Shell</div>
          <h2 class="hero-title">Carry the live session from your desk to your phone.</h2>
          <p class="hero-copy">
            This shell is static by design: the UI, state store, and transport adapters are ready
            before the WebRTC and sideband bridge are wired in. Pair here, sign in if needed, and
            continue the current coding thread without mixing transport logic into the rendering layer.
          </p>
        </div>
        <div class="stat-grid">
          <div class="stat-card">
            <span class="stat-label">Session</span>
            <span class="stat-value">${escapeHtml(state.session.sessionName)}</span>
            <span class="stat-copy">Current Mac session preview</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">Workspace</span>
            <span class="stat-value">Remote shell</span>
            <span class="stat-copy">${escapeHtml(state.session.workspacePath)}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">Transport</span>
            <span class="stat-value">${escapeHtml(state.runtime.webRtcStatus)}</span>
            <span class="stat-copy">Awaiting bridge endpoints</span>
          </div>
        </div>
      </div>
    </section>

    <section class="pairing-grid">
      <article class="panel">
        <h2>Pair with this iPhone</h2>
        <p class="meta-copy">
          Enter the short code shown on your Mac. Pairing is local-state only for now, but the screen
          is ready for a backend-issued challenge.
        </p>
        <div class="input-group">
          <label class="input-label">
            Pair code
            <input
              class="text-input"
              data-pair-code
              inputmode="text"
              autocomplete="one-time-code"
              maxlength="6"
              placeholder="DUCK42"
              value="${escapeHtml(state.pairing.pairCode)}"
            />
          </label>
          <label class="input-label">
            Device name
            <input
              class="text-input"
              data-device-name
              autocomplete="name"
              placeholder="Matt's iPhone"
              value="${escapeHtml(state.pairing.deviceName)}"
            />
          </label>
          <div class="panel-actions">
            <button class="primary-button" type="button" data-action="pair-device">Pair and continue</button>
            <button class="secondary-button" type="button" data-action="continue-guest">Continue as guest</button>
          </div>
        </div>
      </article>

      <article class="panel">
        <h2>Login mode</h2>
        <p class="meta-copy">
          Keep auth separate from pairing. The selected provider only changes the shell state today,
          but the controller is ready for a real login handoff.
        </p>
        <div class="provider-grid">
          <button
            class="provider-button ${state.pairing.provider === "openai" ? "provider-button-active" : ""}"
            type="button"
            data-action="select-provider"
            data-provider="openai"
          >
            OpenAI account
          </button>
          <button
            class="provider-button ${state.pairing.provider === "guest" ? "provider-button-active" : ""}"
            type="button"
            data-action="select-provider"
            data-provider="guest"
          >
            Guest preview
          </button>
        </div>
        <div class="meta-row">
          ${renderPill(`auth ${state.pairing.authState}`, state.pairing.authState)}
          ${renderPill(`provider ${state.pairing.provider}`, state.pairing.provider)}
        </div>
      </article>

      <article class="panel">
        <h2>What happens after pairing</h2>
        <ul class="checklist">
          <li>WebRTC handles browser audio so the phone UI stays thin and responsive.</li>
          <li>Daemon sideband control follows the same session through a future call identifier.</li>
          <li>Transcript and tool rail keep rendering even if transport setup is still incomplete.</li>
        </ul>
      </article>

      <article class="panel">
        <div class="eyebrow">Continue</div>
        <h2>Current session is ready to resume</h2>
        <p class="hero-copy">
          ${escapeHtml(state.session.assistantSummary)}
        </p>
        <div class="meta-row">
          ${renderPill(`status ${state.session.statusLabel}`, state.pairing.resumeAvailable ? "ready_for_offer" : "queued")}
          ${renderPill(`model ${state.session.model}`, "idle")}
        </div>
        <div class="panel-actions">
          <button class="primary-button" type="button" data-action="open-session">Continue current session</button>
          <button class="ghost-button" type="button" data-action="replay-activity">Preview transcript updates</button>
        </div>
      </article>
    </section>
  `;
}

function renderSessionScreen(state) {
  return `
    <section class="panel hero-card">
      <div class="hero-grid">
        <div>
          <div class="eyebrow">Continue Current Session</div>
          <h2 class="hero-title">${escapeHtml(state.session.sessionName)}</h2>
          <p class="hero-copy">
            ${escapeHtml(state.session.assistantSummary)}
          </p>
          <div class="hero-actions">
            <button class="primary-button" type="button" data-action="reconnect-runtime">Reconnect transport</button>
            <button class="secondary-button" type="button" data-action="replay-activity">Replay sideband activity</button>
            <button class="ghost-button" type="button" data-action="toggle-mute">
              ${state.runtime.muted ? "Unmute mic" : "Mute mic"}
            </button>
          </div>
        </div>
        <div class="panel meta-panel">
          <div class="runtime-grid">
            <div class="runtime-row">
              <span class="meta-copy">Workspace</span>
              <span class="runtime-value">${escapeHtml(state.session.workspacePath)}</span>
            </div>
            <div class="runtime-row">
              <span class="meta-copy">Last active</span>
              <span class="runtime-value">${escapeHtml(state.session.lastActiveAt)}</span>
            </div>
            <div class="runtime-row">
              <span class="meta-copy">call_id</span>
              <span class="runtime-value">${escapeHtml(state.runtime.callId ?? "pending bridge")}</span>
            </div>
          </div>
          <div class="meta-row">
            ${renderPill(`webrtc ${state.runtime.webRtcStatus}`, state.runtime.webRtcStatus)}
            ${renderPill(`sideband ${state.runtime.sidebandStatus}`, state.runtime.sidebandStatus)}
            ${renderPill(`voice ${state.runtime.voiceState}`, state.runtime.voiceState)}
          </div>
        </div>
      </div>
    </section>

    <section class="session-grid">
      <section class="transcript-panel">
        <article class="panel">
          <h2>Transcript</h2>
          <p class="meta-copy">
            Assistant and user messages stay in the main lane. Tool detail is separated into the rail so
            the conversation stays readable on iPhone-width screens.
          </p>
          <div class="message-list">
            ${state.transcript.map(renderMessage).join("")}
          </div>
        </article>
      </section>

      <aside class="meta-grid">
        <article class="panel">
          <h2>Tool rail</h2>
          <p class="meta-copy">
            Horizontal on mobile, stacked on larger screens. Designed to accept daemon and Realtime tool events without reworking the transcript.
          </p>
          <div class="tool-rail">
            ${state.tools.map(renderTool).join("")}
          </div>
        </article>

        <article class="panel">
          <h2>Client architecture</h2>
          <div class="runtime-grid">
            <div class="runtime-row">
              <span class="meta-copy">Store</span>
              <span class="runtime-value">Reducer + event dispatch</span>
            </div>
            <div class="runtime-row">
              <span class="meta-copy">WebRTC adapter</span>
              <span class="runtime-value">Session bootstrap boundary</span>
            </div>
            <div class="runtime-row">
              <span class="meta-copy">Sideband adapter</span>
              <span class="runtime-value">call_id follow path</span>
            </div>
          </div>
        </article>
      </aside>
    </section>
  `;
}

function renderBottomDock(state) {
  return `
    <nav class="bottom-dock" aria-label="Primary">
      <div class="dock-grid">
        <button
          class="dock-button ${state.screen === "pairing" ? "dock-button-active" : ""}"
          type="button"
          data-action="open-pairing"
        >
          <strong>Pair</strong>
          <span>${escapeHtml(state.pairing.provider)}</span>
        </button>
        <button
          class="dock-button ${state.screen === "session" ? "dock-button-active" : ""}"
          type="button"
          data-action="open-session"
        >
          <strong>Continue</strong>
          <span>${escapeHtml(state.session.sessionName)}</span>
        </button>
        <button class="dock-button" type="button" data-action="reconnect-runtime">
          <strong>Bridge</strong>
          <span>${escapeHtml(state.runtime.webRtcStatus)}</span>
        </button>
        <button class="dock-button" type="button" data-action="toggle-mute">
          <strong>${state.runtime.muted ? "Muted" : "Mic"}</strong>
          <span>${escapeHtml(state.runtime.voiceState)}</span>
        </button>
      </div>
    </nav>
  `;
}

function renderTool(tool) {
  return `
    <article class="tool-card">
      <div class="tool-meta">
        <span class="tool-name">${escapeHtml(tool.name)}</span>
        ${renderPill(tool.status, tool.status)}
      </div>
      <p class="message-meta">${escapeHtml(tool.durationLabel)}</p>
      <p class="message-meta">${escapeHtml(tool.args)}</p>
      <p class="tool-output">${escapeHtml(tool.outputPreview)}</p>
    </article>
  `;
}

function renderMessage(message) {
  return `
    <article class="message-card message-card-${escapeHtml(message.role)}">
      <div class="meta-row">
        <span class="message-role">${escapeHtml(message.summary)}</span>
        <span class="message-meta">${escapeHtml(message.timestamp)}</span>
      </div>
      <p class="message-text">${escapeHtml(message.text)}</p>
    </article>
  `;
}

function renderPill(label, status) {
  const variant = STATUS_VARIANTS[status] ?? "";
  return `<span class="pill ${variant}">${escapeHtml(label)}</span>`;
}

function renderToast(toast) {
  if (!toast) {
    return "";
  }

  return `
    <div class="toast">
      <span>${escapeHtml(toast)}</span>
      <button type="button" data-action="clear-toast">Dismiss</button>
    </div>
  `;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
