<p align="center">
  <img src="rubber-duck-macOS-Default-1024x1024@1x.png" width="128" alt="Rubber Duck app icon">
</p>

<h1 align="center">Rubber Duck</h1>

<p align="center">
  Open-source voice coding companion for macOS. Bring your own OpenAI API key.
</p>

## How it works

- Hold a hotkey, speak to your codebase, and hear answers spoken back in real time
- Interrupt the assistant mid-sentence — it stops immediately (barge-in)
- Every tool call, diff, and command output scrolls through your terminal via the `duck` CLI
- Two pieces work together: **Rubber Duck.app** (menu bar — mic, speaker, session manager) and the **`duck` CLI** (attach a repo, follow live streams, send typed messages)
- API key stays in macOS Keychain — no middleman

Default shortcuts: `Option+D` to activate voice, `Option+Shift+D` to open Settings.

## Install

Requires an [OpenAI API key](https://platform.openai.com/api-keys) and macOS 15.2+.

**[Download the latest release](https://github.com/mblode/rubber-duck/releases/latest)**, or:

```bash
brew tap mblode/tap
brew install --cask rubber-duck
```

### CLI

```bash
npm install -g rubber-duck
```

Requires Node.js 22+.

## Usage

```bash
# Attach a workspace and stream events
duck ~/projects/myapp

# Send a typed message
duck say "refactor the auth middleware to use async/await"

# List sessions
duck sessions

# Check system health
duck doctor
```

## Updates

- Direct-download installs can use **Check for Updates…** from Settings
- Homebrew installs: `brew upgrade --cask rubber-duck`

## Troubleshooting

- If the menu bar icon is hidden (common with menu bar overflow apps), press `Option+Shift+D` to open Settings directly
- If `duck` commands hang, run `duck doctor` to check daemon health or restart it with `pkill -f duck-daemon`

## License

[MIT](LICENSE.md)
