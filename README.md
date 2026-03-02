<p align="center">
  <img src="icon.png" width="128" alt="Rubber Duck app icon">
</p>

<h1 align="center">Rubber Duck</h1>

<p align="center">
  A voice agent in the macOS menu bar. Hold <code>Option+D</code>, speak to your codebase,
  and hear the answer spoken back — while every file read, edit, and command
  scrolls through your terminal.
</p>

<p align="center">
  BYO OpenAI API key. No subscription. No editor dependency. <a href="LICENSE.md">MIT license</a>.
</p>

## What it does

Hold `Option+D` and speak. The agent:

- Reads files you mention or searches for them
- Edits code and explains what changed
- Runs bash commands in your workspace
- Searches definitions, usages, and patterns with grep
- Speaks the answer back — summarising rather than reading files verbatim

Interrupt at any time. The agent stops immediately (barge-in).

Every step appears in your terminal via `duck [path]`. Nothing is hidden.

Default shortcuts: `Option+D` to activate voice, `Option+Shift+D` to open Settings.

## Install

Requires macOS 15.2+ and an [OpenAI API key](https://platform.openai.com/api-keys).

```bash
brew tap mblode/tap
brew install --cask rubber-duck
```

Or [download the latest DMG](https://github.com/mblode/rubber-duck/releases/latest) directly.

The `duck` CLI is installed automatically on first launch.

## Usage

```bash
# Attach a workspace and stream all events
duck ~/projects/myapp

# Send a typed message to the active session
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
- If `duck` commands hang, run `duck doctor` to check daemon health or restart with `pkill -f duck-daemon`

## License

[MIT](LICENSE.md)
