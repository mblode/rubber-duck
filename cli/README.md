# rubber-duck CLI

Voice-first coding companion CLI.

`duck` is a thin terminal client over a local daemon. The daemon manages Pi RPC
sessions per workspace and streams events over a Unix domain socket.

## Installation

```bash
npm install -g rubber-duck
duck --help
```

Or run ad-hoc:

```bash
npx rubber-duck --help
```

## Core Commands

```bash
duck attach [path]              # attach workspace + create/use session
duck follow [session]           # stream live agent events
duck say <message...>           # send prompt to active session
duck sessions [--all] [--json]  # list sessions
duck use <session>              # set active session
duck new [--name <name>]        # create session
duck abort [session]            # abort current run
duck doctor                     # local + daemon diagnostics
duck export [session] [--out]   # export session HTML
```

`duck follow` and `duck say` support `--json`, `--show-thinking`, and
`--color` / `--no-color`.

## End-to-End Flow

```bash
duck attach .
duck follow
# in another terminal
duck say "run tests and summarize failures only"
duck sessions --all
duck doctor
```

## Runtime Files

All daemon state lives under:

`~/Library/Application Support/RubberDuck/`

- `metadata.json` — workspace/session state
- `config.json` — daemon config
- `duck-daemon.log` — daemon lifecycle log
- `duck-daemon.pid` — daemon PID
- `pi-sessions/` — Pi session files

Socket path defaults to:

`~/Library/Application Support/RubberDuck/duck.sock`

If that path is too long for Unix socket limits, `duck` falls back to:

`$TMPDIR/rubber-duck-<hash>.sock`

## Local Development

```bash
npm install
npm run build
npm run typecheck
npm run lint
npm run verify:ci
npm run validate:say-json-ui
```

## Programmatic API

```ts
import { DaemonClient, createRenderer, SOCKET_PATH } from "rubber-duck";
```

## Requirements

- Node.js >= 22
- Pi binary (resolved in this order): `RUBBER_DUCK_PI_BINARY`, local
  `cli/node_modules/.bin/pi`, then `pi` from `PATH`

## License

[MIT](LICENSE.md)
