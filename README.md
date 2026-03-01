<p align="center">
  <img src="rubber-duck-macOS-Default-1024x1024@1x.png" width="128" alt="RubberDuck app icon">
</p>

<h1 align="center">RubberDuck</h1>

<p align="center">
  Open-source voice-first coding companion for macOS. Bring your own OpenAI API key.
</p>

A [rubber duck debugger](docs/rubber-duck-debugging.md) that talks back. Speak to your codebase through a menu bar app, hear answers spoken back in real time, and watch every tool call, diff, and command output scroll through your terminal. Two pieces work together: **RubberDuck.app** (menu bar — mic, speaker, session manager) and the **`duck` CLI** (attach a repo, follow live streams, send typed messages).

## Features

- **Voice conversation:** Speech-to-speech via the OpenAI Realtime API over a single WebSocket connection.
- **Coding tools:** Read files, edit code, run shell commands, grep, and find — all workspace-confined with a safe mode toggle.
- **Barge-in:** Interrupt the assistant mid-sentence; it stops immediately.
- **Multi-session:** Multiple conversations per repo, background runs, concurrent terminals.
- **`duck` CLI:** Attach workspaces, follow live streams, and send typed messages from any terminal.
- **Terminal transparency:** Every tool call, argument, output chunk, and file edit is visible in the CLI stream.
- **Keychain storage:** Your OpenAI API key stays in macOS Keychain — no middleman.

## Install

Requires an [OpenAI API key](https://platform.openai.com/api-keys) and macOS 15.2+.

**[Download the latest release](https://github.com/mblode/rubber-duck/releases/latest)**, or install with Homebrew:

```bash
brew tap mblode/tap
brew install --cask rubber-duck
```

### CLI

```bash
npm install -g rubber-duck
```

Or link from source after cloning:

```bash
cd cli && npm install && npm run build && npm link
```

Requires Node.js 22+.

## Usage

Default shortcuts: `Option+D` to activate voice, `Option+Shift+D` to open Settings.

### Attach a workspace and stream events

```bash
duck ~/projects/myapp
```

Attaches the directory as the active workspace and streams agent events to your terminal. If a session is already active, it resumes.

### Send a typed message

```bash
duck say "refactor the auth middleware to use async/await"
```

Sends the message to the active session and streams the full response.

### List sessions

```bash
duck sessions
duck sessions --all
```

### Check system health

```bash
duck doctor
```

Reports daemon status, active session, Pi process health, and API key configuration.

## Configuration

**API key:** Open Settings (menu bar → Settings… or `Option+Shift+D`) and paste your OpenAI API key. It is stored in macOS Keychain.

**Coding agent model:** Override the default model used for file edits and tool calls:

```bash
export RUBBER_DUCK_PI_MODEL=gpt-4o
duck ~/projects/myapp
```

Auto-detected from your API key if not set: `ANTHROPIC_API_KEY` → `claude-haiku`, `OPENAI_API_KEY` → `gpt-4o-mini`, `GOOGLE_API_KEY` → `gemini-2.0-flash`.

**Thinking level:** Control reasoning depth (default: `off` for speed):

```bash
export RUBBER_DUCK_PI_THINKING=medium
duck say "audit the database schema for N+1 query risks"
```

Options: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`.

## Updates

- Direct-download installs can use **Check for Updates…** from Settings.
- Homebrew installs: `brew upgrade --cask rubber-duck`.

## Development

### Build and relaunch the app

```bash
xcodebuild -scheme Commandment -configuration Debug build -derivedDataPath /tmp/rubber-duck-build \
  && (pkill -x RubberDuck || true) \
  && rsync -a --delete /tmp/rubber-duck-build/Build/Products/Debug/RubberDuck.app/ /Applications/RubberDuck.app/ \
  && open /Applications/RubberDuck.app
```

### Rebuild the CLI and restart daemon

```bash
cd cli && npm run build && npm link && (pkill -f "duck-daemon|dist/daemon.js" || true)
```

### Run tests

```bash
# Swift unit tests
xcodebuild -scheme Commandment -configuration Debug -destination 'platform=macOS' test \
  -derivedDataPath /tmp/rubber-duck-build

# CLI unit tests
cd cli && npm test

# All E2E tests (require API keys)
make e2e
```

## Troubleshooting

- If the menu bar icon is hidden (common with menu bar overflow apps), press `Option+Shift+D` to open Settings directly.
- If `duck` commands hang, run `duck doctor` to check daemon health or restart it with `pkill -f duck-daemon`.

## Docs

- [Product requirements](docs/prd.md)
- [Rubber duck debugging](docs/rubber-duck-debugging.md)
- [OpenAI Realtime API reference](docs/voice-agents.md)
- [Pi coding agent reference](docs/pi-coding-agent.md)

## License

[MIT](LICENSE.md)
