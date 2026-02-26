<p align="center">
  <img src="rubber-duck-macOS-Default-1024x1024@1x.png" width="128" alt="RubberDuck app icon">
</p>

<h1 align="center">RubberDuck</h1>

<p align="center">
  Open-source voice-first coding companion for macOS. Bring your own OpenAI API key.
</p>

## What it does

RubberDuck is a [rubber duck debugger](docs/rubber-duck-debugging.md) that talks back. Speak to your codebase through a menu bar app, hear answers spoken back in real time, and watch every tool call, diff, and command output scroll through your terminal. Two pieces work together: **RubberDuck.app** (menu bar — mic, speaker, session manager) and the **`duck` CLI** (attach a repo, follow live streams, send typed messages).

## How it works

- **Voice conversation** — speech-to-speech via the OpenAI Realtime API over a single WebSocket connection
- **Coding tools** — read files, edit code, run commands, grep, find — all workspace-confined with safe mode toggle
- **Barge-in** — interrupt the assistant mid-sentence; it stops immediately and either aborts or steers
- **Multi-session** — multiple conversations per repo, background runs, concurrent terminals
- **`duck` CLI** — `duck attach`, `duck follow`, `duck say`, `duck sessions` — thin client over a Unix domain socket
- **Terminal as glass box** — every tool call, argument, output chunk, and file edit is visible in the CLI stream
- **Keychain storage** — your OpenAI API key stays in macOS Keychain, no middleman

## Current state

**v1 (available now):** Transcription and dictation. Hold a hotkey, speak, release — your words appear wherever you're typing. Streams audio to OpenAI, auto-inserts text into the focused app. Default shortcuts: `Option+D` to record, `Option+Shift+D` to open Settings.

**v2 (in development):** Voice-first coding agent with realtime conversation, coding tools, multi-session workspace management, local daemon, and the `duck` CLI. See the [implementation plans](docs/) for details.

## Install

Requires an [OpenAI API key](https://platform.openai.com/api-keys) and macOS 15.2+.

<strong><a href="https://github.com/mblode/rubber-duck/releases/latest">Download the latest release</a></strong>, or:

```bash
brew tap mblode/tap
brew install --cask rubber-duck
```

## Updates

- Direct-download installs can use **Check for Updates...** from the menu bar or Settings
- In-app updates are delivered through Sparkle appcasts with EdDSA signatures
- Homebrew installs can continue updating with `brew upgrade --cask rubber-duck`

## Docs

- [Product requirements](docs/prd.md)
- [Voice agent implementation plan](docs/plan-realtime-voice.md)
- [CLI implementation plan](docs/plan-duck-cli.md)
- [Rubber duck debugging](docs/rubber-duck-debugging.md)
- [OpenAI Realtime API reference](docs/voice-agents.md)
- [Pi coding agent reference](docs/pi-coding-agent.md)

## Troubleshooting

- If RubberDuck is running but you can't see its menu bar icon (for example due to menu bar overflow/hidden-icon apps), press `Option+Shift+D` to open Settings directly.

## License

[MIT](LICENSE.md)
