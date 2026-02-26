# rubber-duck CLI

Voice-first coding companion CLI — attach repos, follow sessions, talk to your code.

## Commands

```bash
npm install              # setup (requires Node >= 22)
npm run build            # tsdown → dist/ (cli.js, index.js, daemon.js)
npm run dev              # tsdown --watch
npm run test             # vitest run
npm run typecheck        # tsc --noEmit
npm run lint             # biome check
npm run lint:fix         # biome check --write
npm run validate:say-json-ui  # deterministic Pi UI flow validation
```

## CLI Commands

```bash
duck attach [path]              # Attach a directory and start a session
duck follow [session]           # Stream live events (--json, --show-thinking, --verbose)
duck say <message...>           # Send a message to the active session
duck sessions [--all]           # List sessions with status
duck use <session>              # Set the active voice session
duck new [--name <name>]        # Create a new session
duck abort [session]            # Abort the current operation
duck doctor                     # Check system health
duck export [session] [--out]   # Export session to HTML
```

## Architecture

```
src/
  cli.ts                    # Commander entry point (9 subcommands)
  index.ts                  # Public API exports (types + renderer + client)
  types.ts                  # All shared types: Pi RPC, daemon IPC, domain model
  constants.ts              # Paths: ~/Library/Application Support/RubberDuck/
  utils.ts                  # generateId, workspaceId, formatTimestamp, findGitRoot
  client.ts                 # DaemonClient: Unix socket NDJSON client
  ensure-daemon.ts          # Auto-start daemon with exponential backoff
  commands/
    attach.ts               # Resolve path → daemon attach → print session
    follow.ts               # Subscribe to events → pipe through renderer
    say.ts                  # Follow + send prompt → wait for agent_end
    sessions.ts             # Query sessions → format table
    use.ts                  # Set active voice session
    new.ts                  # Create new session in workspace
    abort.ts                # Forward abort to Pi process
    doctor.ts               # Local + daemon health checks
    export.ts               # Forward export_html to Pi
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

Methods: `ping`, `attach`, `follow`, `unfollow`, `extension_ui_response`, `say`, `sessions`, `use`, `new`, `abort`, `doctor`, `export`, `get_state`

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
