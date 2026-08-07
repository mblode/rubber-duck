<div align="center">

# [Rubber Duck](https://blode.co/rubber-duck)

**Press a hotkey, talk through your code out loud, and hear the answer back**

Point the menu bar agent at a repo and it reads your files, greps the tree, runs commands, and makes edits while you speak.

</div>

## Demo

Read how it works, and download the app.

<p>
<a href="https://blode.co/rubber-duck">
<img alt="Visit the site" src=".github/assets/demo.svg" width="200" />
</a>
</p>

## Install

```bash
brew install --cask mblode/tap/rubber-duck
```

Or [download the latest DMG](https://github.com/mblode/rubber-duck/releases/latest). Either way, the app pulls down the matching `duck` CLI on first launch and symlinks it into `/usr/local/bin`.

## Quickstart

```bash
duck ~/Code/blode-icons
```

The menu bar app switches to that workspace straight away. Press `Option+D`, ask your question out loud, and the reply comes back as speech while the events stream into your terminal. Turn taking is automatic, talking over the reply cuts it off, and pressing the hotkey again ends the session.

## Commands

| Command | Description |
|---------|-------------|
| `duck [path]` | Attach a workspace and stream its events, defaulting to the current directory |
| `duck say "fix the auth bug"` | Send a typed message to the active session |
| `duck sessions` | List sessions, or `--all` for every workspace |
| `duck doctor` | Check the daemon, socket, model, and provider keys |
| `duck remote` | Manage the daemon's remote control plane |

Add `--json` to `say` or `sessions` for raw NDJSON.

## Requirements

- macOS 15.2 Sequoia or later.
- An [OpenAI API key](https://platform.openai.com/api-keys), kept in the macOS Keychain. You pay for the minutes you talk, with no subscription.

## Notes

- Audio goes to the OpenAI Realtime API as 24 kHz mono. Tool calls run locally, through a daemon on a Unix socket, so your own machine is what opens the file.
- The app updates itself through Sparkle. **Check for Updates** in Settings forces a check.
- If the menu bar icon is hidden, `Option+Shift+D` opens Settings directly.
- If `duck` hangs, run `duck doctor`, then `pkill -f duck-daemon` to force a restart.

## License

MIT

---

Crafted by [<img src="https://blode.co/avatar-circle.png" width="20" align="top" />](https://blode.co) [Matthew Blode](https://blode.co)
