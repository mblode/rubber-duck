# Rubber Duck

macOS menu bar voice coding agent — BYO OpenAI API key. Swift 5 / SwiftUI + KeyboardShortcuts SPM.

## Commands

- `open RubberDuck.xcodeproj` — Open in Xcode
- `xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' build -derivedDataPath /tmp/rubber-duck-build` — Build from CLI
- `xcodebuild -scheme Commandment -configuration Release -destination 'generic/platform=macOS' build -derivedDataPath /tmp/rubber-duck-build` — Release build
- `xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' test -derivedDataPath /tmp/rubber-duck-build` — Run tests
- `make unused` — Find unused Swift declarations (Periphery — Knip equivalent for Swift)
- `xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' build -derivedDataPath /tmp/rubber-duck-build && (pkill -x "Rubber Duck" || true) && rsync -a --delete "/tmp/rubber-duck-build/Build/Products/Debug/Rubber Duck.app/" "/Applications/Rubber Duck.app/" && open "/Applications/Rubber Duck.app"` — Build, replace installed app, relaunch (avoids stale bundle)

### Rebuild Shortcuts

- `xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' build -derivedDataPath /tmp/rubber-duck-build && (pkill -x "Rubber Duck" || true) && rsync -a --delete "/tmp/rubber-duck-build/Build/Products/Debug/Rubber Duck.app/" "/Applications/Rubber Duck.app/" && open "/Applications/Rubber Duck.app"` — Rebuild and replace the installed macOS app
- `cd cli && npm run build && npm link && (pkill -f "rubber-duck-daemon|dist/daemon.js" || true)` — Rebuild/relink CLI and force daemon restart so `rubber-duck` uses latest code

### CLI Commands (`cli/`)

- `cd cli && npm install` — Install CLI dependencies
- `cd cli && npm run build` — Build `rubber-duck`, `rubber-duck-daemon`, and library exports
- `cd cli && npm run typecheck` — TypeScript checks
- `cd cli && npm run lint` — Biome checks
- `cd cli && npm run verify:ci` — Build + typecheck + lint + help smoke
- `cd cli && node dist/daemon.js --verbose` — Run daemon in foreground for debugging
- `cd cli && node dist/cli.js .` — Attach current workspace and start streaming
- `cd cli && node dist/cli.js say "list files"` — Send prompt to active session

### CLI Binary (standalone, no Node required)

- `make cli-binary` — Build standalone universal (arm64+x64) `rubber-duck` binary via esbuild+pkg into `cli-bin/`
- `make embed-cli` — Copy `cli-bin/rubber-duck` into `RubberDuck/CLI/` for Xcode embedding (run before building app)
- `make embed-cli-optional` — Embed if already built, skip otherwise (safe for dev builds)

### E2E Tests (require API keys)

- `echo "sk-..." > /tmp/rubber-duck-live-realtime-test` — Set up Swift Realtime live test key
- `make e2e-swift` — Run Swift Realtime full-conversation E2E (requires `/tmp/rubber-duck-live-realtime-test`)
- `make e2e-cli` — Run CLI daemon integration E2E (requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`)
- `make e2e-smoke` — Run CLI shell smoke test (requires API key + built CLI)
- `make e2e` — Run all E2E tests

## Setup

- Requires Xcode 16+ and macOS 15.2+ SDK
- SPM dependency: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) v2+
- API key (OpenAI) stored in macOS Keychain, configured via Settings window

## Gotchas

- Audio is streamed at 24 kHz PCM16 mono to the OpenAI Realtime API
- The app runs as a menu bar agent (`LSUIElement = true`) — no dock icon or main window. Do not add a `WindowGroup` or `DocumentGroup` scene
- If UI changes do not appear, you are likely running a stale bundle. Always replace `/Applications/Rubber Duck.app` from `/tmp/rubber-duck-build/Build/Products/Debug/Rubber Duck.app` and relaunch from `/Applications`.
- Settings window opening is centralized in `SettingsWindowController.shared.show()`; do not use responder-chain selectors like `showSettingsWindow:` for new code paths
- Setup checklist state is stored in `AppConfigManager` (`setupGuideDismissed`) and surfaced in menu + Settings > Setup; keep skip/reset behavior non-blocking
- HotkeyManager is `@MainActor` — removing this will cause KeyboardShortcuts crashes on background threads
- Settings changes propagate via `@EnvironmentObject` (`AppConfigManager`) — do not replace with NotificationCenter
- Default global hotkeys are Option+D (activate voice agent) and Option+Shift+D (open Settings) — configured via KeyboardShortcuts in `HotkeyManager`
- CLI uses a local daemon + Unix socket. Default socket path is `~/Library/Application Support/RubberDuck/daemon.sock`; if path length is too long, it falls back to `$TMPDIR/rubber-duck-<hash>.sock`.
- CLI daemon runtime files: `~/Library/Application Support/RubberDuck/{metadata.json,config.json,rubber-duck-daemon.log,rubber-duck-daemon.pid,pi-sessions/}`.
- CLI `follow` and `say` automatically handle Pi `extension_ui_request` events via `@clack/prompts` and send `extension_ui_response` back through the daemon.
- CLI daemon defaults to `gpt-4o-mini` when `OPENAI_API_KEY` is set. Override with `RUBBER_DUCK_PI_MODEL` env var. Thinking defaults to `off` for speed; override with `RUBBER_DUCK_PI_THINKING`.
- Swift app connects to `daemon.sock` via `DaemonSocketClient` (Network.framework NWConnection, `@MainActor`). If daemon absent the app runs normally — voice tools return an error, workspace switching falls back to 2s polling.
- Voice tool calls (`read_file`, `write_file`, `edit_file`, `bash`, `grep_search`, `find_files`) are executed by `cli/src/daemon/voice-tools.ts` via the `voice_tool_call` daemon method. Swift no longer implements these tools locally.
- Workspace switching from `rubber-duck [path]` → Swift menu bar is instant via `voice_session_changed` daemon push (no polling delay when daemon is running).
- CLI binary is embedded in `Contents/MacOS/rubber-duck` (built via `make cli-binary && make embed-cli`). The app auto-installs symlinks in `/usr/local/bin` on first launch via `CLIInstaller`. Run `make embed-cli` before building the Xcode project if you need the binary present in the archive.
- The standalone `rubber-duck` binary acts as both CLI and daemon — daemon mode is activated when `argv[0]` ends in `rubber-duck-daemon` (via symlink) or `--daemon` flag is passed.

## Conventions

- Network retries use exponential backoff (1s, 2s, 4s) with max 3 attempts
- Logging goes through `Logger.shared` — use `logInfo()`, `logError()`, `logDebug()` global functions
- Bundle ID: `co.blode.rubber-duck`

## Distribution

- `make build` — Release build
- `make cli-build` — Build CLI (TypeScript → dist/)
- `make cli-binary` — Build standalone universal binary (esbuild CJS bundle + pkg + lipo)
- `make cli-test` — Run CLI tests (passes when no tests are present)
- `make dmg` — Build + create DMG (requires `brew install create-dmg`)
- `make notarize` — Build + DMG + notarize (requires Apple Developer credentials in env)
- `make clean` — Remove build artifacts
- Release: `git tag v1.0.0 && git push origin main --tags` — GitHub Actions handles build/sign/notarize/release
- Secrets (GitHub): `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `NOTARIZE_APPLE_ID`, `NOTARIZE_PASSWORD`
- Homebrew template: `homebrew/rubber-duck.rb` — copy to `mblode/homebrew-tap` repo
