# rubber-duck CLI

Voice-first coding companion CLI — one-command attach + stream, with `say` for prompts.

## Commands

```bash
npm install              # setup (requires Node >= 22)
npm run build            # tsdown → dist/ (cli.js, index.js, daemon.js)
npm link                 # relink local `duck` binary after rebuild
npm run dev              # tsdown --watch
npm run test             # vitest run
npm run typecheck        # tsc --noEmit
npm run lint             # biome check
npm run lint:fix         # biome check --write
npm run validate:say-json-ui  # deterministic Pi UI flow validation
```

## Rebuild

```bash
cd cli && npm run build && npm link && (pkill -f "duck-daemon|dist/daemon.js" || true)
# rebuild + relink CLI, then restart daemon so `duck` picks up new dist files
```

## CLI Commands

```bash
duck [path]                     # Attach (or resume) workspace + stream events
duck say <message...>           # Send a message to the active session
duck sessions [--all]           # List sessions with status
duck doctor                     # Check system health
```

## Architecture

```
src/
  cli.ts                    # Commander entry point (default action + core commands)
  index.ts                  # Public API exports (types + renderer + client)
  types.ts                  # All shared types: Pi RPC, daemon IPC, domain model
  constants.ts              # Paths: ~/Library/Application Support/RubberDuck/
  utils.ts                  # generateId, workspaceId, formatTimestamp, findGitRoot
  client.ts                 # DaemonClient: Unix socket NDJSON client
  ensure-daemon.ts          # Auto-start daemon with exponential backoff
  commands/
    default.ts              # `duck [path]` attach/resume + follow
    follow.ts               # Follow stream engine (Pi + app history)
    say.ts                  # Follow + send prompt → wait for agent_end
    sessions.ts             # Query sessions → format table
    doctor.ts               # Local + daemon health checks
  daemon/
    main.ts                 # Entry point: PID check, init, listen, shutdown
    metadata-store.ts       # Atomic JSON persistence for workspaces/sessions
    pi-process.ts           # Pi RPC subprocess: NDJSON stdin/stdout, request correlation
    pi-process-manager.ts   # Session ID → PiProcess map, spawn/kill
    socket-server.ts        # Unix domain socket server, per-client NDJSON
    request-handler.ts      # Route daemon requests to business logic
    event-bus.ts            # Pub/sub: subscribe(clientId, sessionId, handler)
    health.ts               # 30s periodic Pi process liveness check
  renderer/
    index.ts                # Factory: createRenderer(options) → text or JSON
    types.ts                # EventRenderer interface, RendererPiEvent union
    colors.ts               # styleText wrappers respecting NO_COLOR
    format.ts               # formatTag, formatToolArgs, truncate
    tool-tracker.ts         # Diff accumulated tool output, emit only new lines
    text-renderer.ts        # Pretty-print with [prefix] tags, streaming deltas
    json-renderer.ts        # NDJSON pass-through
    ui-handler.ts           # @clack/prompts for extension UI requests
```

## Data Flow

```
RubberDuck.app (voice) ──► duck CLI ──► daemon (Unix socket) ──► Pi (RPC subprocess)
                                              │
                                              ├── MetadataStore (metadata.json)
                                              ├── EventBus (pub/sub per session)
                                              └── SocketServer (NDJSON per client)
```

## Daemon IPC Protocol

NDJSON over Unix socket at `~/Library/Application Support/RubberDuck/duck.sock`.
If that path exceeds Unix socket length limits, daemon and CLI fall back to
`$TMPDIR/rubber-duck-<hash>.sock`.

- **Request**: `{ id, method, params }`
- **Response**: `{ id, ok, data?, error? }`
- **Event**: `{ event, sessionId, data }` (pushed to subscribed clients)

Methods: `ping`, `attach`, `follow`, `unfollow`, `extension_ui_response`, `say`, `sessions`, `abort`, `doctor`, `get_state`

## Gotchas

- **ESM only**: `"type": "module"`. Use `.js` extensions in imports.
- **Triple build**: tsdown produces `cli.js` (shebang), `index.js` (library + .d.ts), `daemon.js` (shebang). Do not merge.
- **Biome via ultracite**: Run `npm exec -- ultracite fix` instead of calling biome directly.
- **No chalk/ora**: Use `node:util` styleText for colors. Use `@clack/prompts` for interactive UI.
- **Pi RPC**: Pi communicates via JSON stdin/stdout when spawned with `--mode rpc`. Events are pushed, commands are request/response correlated by `id`.
- **Pi binary resolution**: `constants.ts` resolves in this order: `RUBBER_DUCK_PI_BINARY`, local `node_modules/.bin/pi`, then `pi` from `PATH`.
- **Session resolution**: Daemon accepts session name, full ID, or unambiguous prefix. Default is the active voice session.
- **Daemon auto-start**: `ensureDaemon()` checks socket → PID file → spawns detached → polls with exponential backoff.
- **Metadata path**: `~/Library/Application Support/RubberDuck/metadata.json` — atomic writes via rename.
- **Runtime config/log**: daemon ensures `config.json` and appends lifecycle lines to `duck-daemon.log` in app support.
- **UI extension requests**: `follow`/`say` auto-handle `extension_ui_request` via `@clack/prompts` and forward responses with daemon method `extension_ui_response`.
- **Pi model config**: `RUBBER_DUCK_PI_MODEL` sets `--model` passed to Pi (e.g. `haiku`, `gpt-4o-mini`, `sonnet`). Without it, the daemon auto-detects a fast model from your API key: `ANTHROPIC_API_KEY` → `haiku`, `OPENAI_API_KEY` → `gpt-4o-mini`, `GOOGLE_API_KEY` → `gemini-2.0-flash`. Override with `piModel` in `config.json`.
- **Pi thinking level**: `RUBBER_DUCK_PI_THINKING` sets `--thinking` level (default: `off` for speed). Options: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`. Override with `piThinking` in `config.json`.
- **`setStatus` messages**: Internal Pi status events (e.g. `Thinking…`) are suppressed in default output. Use `--verbose` to see them.
