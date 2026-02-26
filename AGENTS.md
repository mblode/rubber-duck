# RubberDuck

macOS menu bar voice coding agent — BYO OpenAI API key. Swift 5 / SwiftUI + KeyboardShortcuts SPM.

## Commands

- `open RubberDuck.xcodeproj` — Open in Xcode
- `xcodebuild -scheme Commandment -configuration Debug build -derivedDataPath /tmp/rubber-duck-build` — Build from CLI
- `xcodebuild -scheme Commandment -configuration Release build -derivedDataPath /tmp/rubber-duck-build` — Release build
- `xcodebuild -scheme Commandment -configuration Debug -destination 'platform=macOS' test -derivedDataPath /tmp/rubber-duck-build` — Run tests
- `xcodebuild -scheme Commandment -configuration Debug build -derivedDataPath /tmp/rubber-duck-build && (pkill -x RubberDuck || true) && rsync -a --delete /tmp/rubber-duck-build/Build/Products/Debug/RubberDuck.app/ /Applications/RubberDuck.app/ && open /Applications/RubberDuck.app` — Build, replace installed app, relaunch (avoids stale bundle)

### CLI Commands (`cli/`)

- `cd cli && npm install` — Install CLI dependencies
- `cd cli && npm run build` — Build `duck`, `duck-daemon`, and library exports
- `cd cli && npm run typecheck` — TypeScript checks
- `cd cli && npm run lint` — Biome checks
- `cd cli && npm run verify:ci` — Build + typecheck + lint + help smoke
- `cd cli && node dist/daemon.js --verbose` — Run daemon in foreground for debugging
- `cd cli && node dist/cli.js attach .` — Attach current workspace and create/use session
- `cd cli && node dist/cli.js follow` — Stream session events
- `cd cli && node dist/cli.js say "list files"` — Send prompt to active session

## Setup

- Requires Xcode 16+ and macOS 15.2+ SDK
- SPM dependency: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) v2+
- API key (OpenAI) stored in macOS Keychain, configured via Settings window

## Gotchas

- Audio is streamed at 24 kHz PCM16 mono to the OpenAI Realtime API
- The app runs as a menu bar agent (`LSUIElement = true`) — no dock icon or main window. Do not add a `WindowGroup` or `DocumentGroup` scene
- If UI changes do not appear, you are likely running a stale bundle. Always replace `/Applications/RubberDuck.app` from `/tmp/rubber-duck-build/Build/Products/Debug/RubberDuck.app` and relaunch from `/Applications`.
- Settings window opening is centralized in `SettingsWindowController.shared.show()`; do not use responder-chain selectors like `showSettingsWindow:` for new code paths
- Setup checklist state is stored in `TranscriptionManager` (`setupGuideDismissed`) and surfaced in menu + Settings > Setup; keep skip/reset behavior non-blocking
- HotkeyManager is `@MainActor` — removing this will cause KeyboardShortcuts crashes on background threads
- Settings changes propagate via `@EnvironmentObject` (`TranscriptionManager`) — do not replace with NotificationCenter
- Default global hotkeys are Option+D (activate voice agent) and Option+Shift+D (open Settings) — configured via KeyboardShortcuts in `HotkeyManager`
- CLI uses a local daemon + Unix socket. Default socket path is `~/Library/Application Support/RubberDuck/duck.sock`; if path length is too long, it falls back to `$TMPDIR/rubber-duck-<hash>.sock`.
- CLI daemon runtime files: `~/Library/Application Support/RubberDuck/{metadata.json,config.json,duck-daemon.log,duck-daemon.pid,pi-sessions/}`.
- CLI `follow` and `say` automatically handle Pi `extension_ui_request` events via `@clack/prompts` and send `extension_ui_response` back through the daemon.

## Conventions

- Network retries use exponential backoff (1s, 2s, 4s) with max 3 attempts
- Logging goes through `Logger.shared` — use `logInfo()`, `logError()`, `logDebug()` global functions
- Bundle ID: `co.blode.rubber-duck`

## Distribution

- `make build` — Release build
- `make cli-build` — Build CLI
- `make cli-test` — Run CLI tests (passes when no tests are present)
- `make dmg` — Build + create DMG (requires `brew install create-dmg`)
- `make notarize` — Build + DMG + notarize (requires Apple Developer credentials in env)
- `make clean` — Remove build artifacts
- Release: `git tag v1.0.0 && git push origin main --tags` — GitHub Actions handles build/sign/notarize/release
- Secrets (GitHub): `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `NOTARIZE_APPLE_ID`, `NOTARIZE_PASSWORD`
- Homebrew template: `homebrew/rubber-duck.rb` — copy to `mblode/homebrew-tap` repo
