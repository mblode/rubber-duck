Product requirements document: Rubber Duck (macOS menu bar voice + CLI companion, powered by Pi CLI)

1. Product summary

Rubber Duck is a voice-first coding companion for macOS. You talk out loud; it answers out loud; and it can inspect and modify the current codebase by driving Pi CLI as the underlying coding agent. The terminal stays as the “glass box” where you can see the full transcript, tool calls, tool output, diffs, and session history. Voice is the primary interface; the CLI is the primary audit trail.

The system is two pieces: Rubber Duck.app (menu bar UI + mic/speaker + session manager + local daemon) and a small CLI (“duck”) that attaches a repo, follows streams, and offers simple session control. Pi runs headless in RPC mode behind the scenes to provide the agent loop, tools, and session persistence. ([GitHub][1])

2. Goals and non-goals

Goals

Rubber Duck.app must enable a low-friction, interruption-friendly, back-and-forth voice conversation about the current directory, where the assistant can search/read files, run bash commands, and propose or apply edits through Pi’s tool harness. ([GitHub][2])

The CLI must show everything important: user utterances (as text), assistant responses (as text), tool calls, tool streaming output, exit codes, and any file edits. It must be usable from any terminal (Ghostty, iTerm2, Terminal.app, Zed terminal) because it’s just a normal CLI printing a stream.

Multi-session must be first-class: multiple repos and multiple conversation sessions can coexist, with clean switching and concurrent background runs, while keeping voice output tied to exactly one active session at a time.

Best possible dev experience: install once, attach a repo in one command, talk immediately, and never lose track of context or history.

Non-goals (for v1)

Universal “context from focused window” (Chrome tab, editor selection, etc.) as the main path. It can be added later, but v1 is intentionally anchored on the repo you attach via CLI.

Replacing Pi’s interactive TUI. Rubber Duck uses Pi headlessly and exposes only the essentials in a simpler, voice-driven workflow.

3. Users and primary jobs-to-be-done

Primary user: a developer working locally in a repo who wants rubber-duck debugging, codebase Q&A, and “do the next action” help without typing long prompts.

Jobs-to-be-done:

Understand code: “Where is X defined, how does Y flow, why is this failing?”

Change code: “Make a safe refactor, add a feature, fix a bug, update tests.”

Navigate and verify: “Run the tests, inspect failing output, propose the minimal fix.”

Keep momentum: stay in flow with voice, while keeping a trustworthy terminal record of what happened.

4. Core UX principles

Voice-first, terminal-transparent. The spoken experience is conversational and short; the terminal shows the full detail.

One repo context by default. The assistant never guesses the repo; it uses the currently attached workspace from the CLI unless you explicitly switch.

Interruptions are instant. Speaking while it’s talking stops TTS immediately and either aborts the current agent run or queues a “steer” message depending on your mode.

No hidden automation. Every tool call and file edit is visible in the CLI stream.

5. Product surface area

5.1 Rubber Duck.app (menu bar)

Responsibilities

Capture audio, run VAD, run speech-to-text (streaming partials where possible), and render a minimal “recording / thinking / speaking” status in the menu bar.

Speak responses via TTS with barge-in (immediate stop on user speech).

Act as the local “daemon” that owns sessions, spawns Pi processes, routes events to CLI clients, and persists metadata.

Minimal UI

Menu bar icon reflects state: idle, listening, busy, speaking.

Popover shows: active workspace (repo path), active session name/id, and a one-click “switch session” list for that workspace.

A single toggle: “Background sessions speak” (default off).

A single toggle: “Auto-abort on barge-in” (default on).

5.2 duck CLI

Responsibilities

Attach the current directory as a workspace.

Follow and render the live event stream in the terminal.

Send typed messages (optional, but useful).

Simple session management commands.

The CLI never executes tools directly; it’s a client of the app/daemon. Pi and tool execution remain under the daemon’s control so voice and terminal stay in sync.

6. Pi integration requirements

Pi is used as the agent runtime, tool harness, and session store.

Pi is started per session in RPC mode: `pi --mode rpc ...` which exposes a JSON protocol over stdin/stdout, with command responses and a rich event stream for message deltas and tool execution updates. ([GitHub][1])

Rubber Duck relies on these Pi behaviors:

Pi has a small default toolset (read/write/edit/bash) appropriate for codebase work, and is meant to be extended via skills/extensions if needed. ([GitHub][2])

Pi sessions are persisted as JSONL files with tree structure and support branching and resuming; Pi can continue recent sessions and switch sessions explicitly. ([GitHub][2])

Pi RPC supports queueing behavior during streaming: prompt with `streamingBehavior` or explicit `steer` / `follow_up`, and explicit `abort`. ([GitHub][1])

Pi RPC emits event types needed for a terminal “glass box”: `message_update` (text deltas, toolcall deltas) and `tool_execution_*` (streaming stdout) among others. ([GitHub][1])

7. Session model and how multiple sessions work

Terminology

Workspace: a directory root (usually a repo root) attached from a terminal via `duck attach`. Identified as workspaceId = hash(path).

Session: a single Pi session file + one running Pi RPC subprocess bound to one workspace. Sessions can be named. Pi can report `sessionId`, `sessionFile`, `sessionName` via `get_state`. ([GitHub][1])

Run: one agent “turn” started by a user prompt, potentially containing tool calls and streamed output.

Concurrency rules

Multiple sessions can exist at the same time across workspaces and within the same workspace.

Multiple sessions can run concurrently (multiple Pi subprocesses). This enables “background work” while you talk in a different session.

Voice is always attached to exactly one “active voice session” at a time. If other sessions produce output, it goes to terminal streams and optionally to a notification, but not spoken by default.

Each terminal can “follow” one session (or all sessions) independently, so you can open multiple terminals and monitor multiple sessions.

Switching behavior

Switching the active voice session is explicit (menu bar popover list or `duck use <session>`). Switching does not kill other sessions; it just changes where new voice utterances go.

When you switch, Rubber Duck sends Pi `get_state` for the target and prints a short “switched context” line to all subscribed CLI clients for that session.

Session persistence

By default, Rubber Duck uses a dedicated session directory (e.g. `~/Library/Application Support/RubberDuck/pi-sessions/`) to avoid interfering with a user’s existing Pi workflows. Pi supports `--session-dir` and `--no-session` behaviors for this. ([GitHub][1])

Optional advanced setting: “Use global Pi sessions” to reuse Pi’s normal session location and resume behavior.

8. End-to-end user flows

8.1 First run (best DX)

User installs Rubber Duck (app) and duck (CLI).

User runs in a repo:

`duck attach`

This launches the daemon (if needed), registers the workspace, creates or resumes the default session for that workspace, and prints:

“Attached: /path/to/repo (session duck-1). Use: duck follow”

User runs:

`duck follow`

Now the terminal becomes the live stream for that session.

User presses global hotkey (or clicks menu bar icon) and speaks. Rubber Duck transcribes and sends the text to Pi via RPC `prompt`. ([GitHub][1])

While Pi runs tools, the CLI prints tool execution start/update/end events and message deltas.

When the assistant produces text, Rubber Duck speaks it. The terminal prints the full text as well.

8.2 Interruptions (barge-in)

If the assistant is speaking and the user starts talking:

Stop TTS immediately.

If “Auto-abort on barge-in” is enabled, Rubber Duck sends Pi `abort` (and, if a tool is mid-execution, `abort_bash` where appropriate). ([GitHub][1])

If “Auto-abort” is disabled, Rubber Duck sends the new user speech as a steering message to Pi (`steer`), which is delivered after the current tool completes and skips remaining planned tools. ([GitHub][1])

The CLI always prints a line indicating whether the run was aborted or steered.

8.3 Multiple sessions in one repo

User wants two threads: “debug test failure” and “refactor module”.

`duck new --name debug-tests`
`duck new --name refactor-module`

These create two Pi sessions bound to the same workspace. One becomes active in the CLI (and optionally as voice session).

User opens two terminal windows:

Terminal A: `duck follow debug-tests`
Terminal B: `duck follow refactor-module`

User can switch voice between them:

`duck use debug-tests`
or via menu bar.

8.4 Background work

User says: “In the refactor session, run the test suite and tell me if anything fails, but don’t talk unless it fails.”

Rubber Duck sends the prompt to that session and marks it “background”.

CLI shows the work in that session stream.

If the run ends successfully, Rubber Duck shows a notification; no speech.

If it fails, Rubber Duck optionally announces a one-line summary and switches the menu bar indicator to “attention”.

9. CLI command design (simple)

Command names assume the binary is `duck`.

`duck attach [path]`
Attach current directory (or provided path) as a workspace. Creates or resumes the default session for that workspace and sets it as the active voice session.

`duck follow [session]`
Stream events for a session to stdout. If session is omitted, follows the active session for the current workspace (if attached) or the global active session.

`duck say "message"`
Send a typed message to the active voice session (same as speaking, but text). Prints streaming output in the current terminal and returns non-zero on agent failure if detectable.

`duck sessions [--all]`
List sessions for the current workspace (default) or all workspaces.

`duck use <session>`
Set the active voice session. This is what the menu bar uses for the next voice turn.

`duck new [--name NAME] [--no-resume]`
Create a fresh session in the current workspace and switch to it.

`duck abort [session]`
Abort the currently running agent operation for the session (default: active session). Uses Pi RPC `abort`. ([GitHub][1])

`duck doctor`
Checks: Rubber Duck daemon reachable, microphone permission, Pi installed and runnable, providers configured.

Optional but useful:

`duck export [session] [--out file.html]`
Calls Pi RPC `export_html` and prints the output path. ([GitHub][1])

10. Terminal output requirements

The CLI output must be readable as a stream and grep-friendly.

It must clearly distinguish:

User utterance (transcript)

Assistant text (streamed deltas allowed; final message must be clearly ended)

Tool call start with tool name and args

Tool output streaming chunks and final result

Abort/steer events

Session boundaries (session id/name/workspace path)

A minimal default format is line-oriented with prefixes, but it can optionally offer `--json` to dump raw events.

11. Daemon / local server requirements

Rubber Duck runs a local daemon process (can be inside the app or a helper) that:

Owns the “active session” mapping.

Spawns and supervises Pi subprocesses (one per session) in RPC mode.

Maintains a publish/subscribe event bus to multiple CLI clients.

Routes commands from CLI to the correct session’s Pi stdin.

Fan-outs Pi stdout event streams to subscribed CLI clients.

Stores a small metadata DB (SQLite or JSON) for workspace list, last active session per workspace, session display names, and last seen timestamps.

Security boundary: daemon only binds to localhost or (preferably) a Unix domain socket in the user’s home directory with filesystem permissions restricting access.

12. Voice behavior requirements

Speech-to-text must be fast enough for natural back-and-forth, with partials shown in the menu bar popover while speaking.

Text-to-speech must be interruptible immediately.

The spoken content should avoid reading raw diffs and long code blocks. The default policy:

If assistant text contains code blocks longer than N lines, Rubber Duck speaks a short summary and says “details are in the terminal.”

If assistant text is short, speak it verbatim.

This keeps you in a voice conversation without making the assistant “sound like a terminal”.

13. Tooling and safety requirements (practical defaults)

Default capabilities

Read/search/inspect is always enabled.

Write/edit and bash are enabled by default for “best DX”, but Rubber Duck provides a single “Safe mode” toggle that disables write/edit and restricts bash to an allowlist (e.g., git, rg, sed/awk, tests). This is a product-level gate, independent of Pi.

Workspace confinement

All file operations and bash commands must be executed with cwd = workspace root and must be prevented from escaping the workspace via `..`, symlinks (optional), or absolute paths unless explicitly allowed.

Network transparency

If the agent runs a command that makes network calls (curl, npm install, etc.), the CLI must show it clearly. Safe mode can block these.

14. Configuration

User-level config (stored in `~/Library/Application Support/RubberDuck/config.json` or similar):

Default model/provider selection (delegated to Pi’s provider config where possible)

Safe mode toggle

Auto-abort on barge-in

Background completion notifications

Session storage mode (Rubber Duck-managed session dir vs global Pi session dir)

Project-level customization

Rubber Duck ships a recommended `.pi/SYSTEM.md` template that makes responses voice-friendly and tool-transparent, leveraging Pi’s system prompt override mechanism. ([GitHub][2])

15. Performance and reliability requirements

Startup: `duck attach` should return in under ~300ms once the daemon is running (excluding first-time Pi install).

Streaming: tool output should appear in the CLI with low latency (sub-second) while the tool runs.

Failure modes must be explicit:

If Pi is missing, `duck doctor` and `duck attach` must provide a single actionable fix (install Pi).

If model auth is missing, tell the user exactly which env var or provider setup is needed (and offer `duck login` if implemented).

If the daemon dies, the CLI should show “daemon disconnected” and exit non-zero.

16. Implementation notes that constrain the PRD

Use Pi RPC mode rather than scraping terminal output. It is explicitly designed for embedding and provides the right primitives for prompt/steer/follow-up/abort plus structured streaming events and session control. ([GitHub][1])

Use Pi’s session model rather than inventing a new one. Pi already persists sessions as JSONL trees, supports resume/new/switch/fork, and reports session state in RPC. ([GitHub][2])

17. Definition of done for v1

A user can install Pi and Rubber Duck, run `duck attach` in a repo, run `duck follow`, press a hotkey, and have a back-and-forth voice conversation that can search the codebase, run commands, and propose changes, with all tool calls and output visible in the terminal.

A user can create two sessions in the same repo, follow them in two terminals, switch the active voice session, and run one session in the background while talking to another.

Interruptions work reliably: speaking stops TTS immediately and either aborts the run or steers it, and the terminal reflects what happened.

If you want, I can also include a concrete event schema for the daemon-to-CLI stream (NDJSON message types and fields) that maps directly onto Pi’s RPC events so the CLI implementation stays tiny.

[1]: https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/docs/rpc.md "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/README.md "raw.githubusercontent.com"
