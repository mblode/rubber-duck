"use client";
"use no memo";

import { useMockClock } from "@/components/mocks/use-mock-clock";
import { cn } from "@/lib/utils";

/**
 * The hero demonstration: the split ledger.
 *
 * A voice product's obvious hero is a waveform, and a waveform proves the
 * microphone works, which nobody doubts. The claim this app makes is that a
 * spoken sentence turns into a tool call against a real repository — so both
 * halves have to be in one frame at the same time, and the reader has to be
 * able to see one cause the other. That is the whole reason this is two panes
 * rather than one prettier transcript.
 *
 * Four details do the work, and each was chosen over a more obvious one:
 *
 * 1. The ledger fills in *behind* the conversation, one row per beat. A single
 *    "3 tools used" summary would be smaller and would say nothing: what is
 *    persuasive is watching `grep` land before the answer does.
 * 2. The last row opens into a three-line unified diff. It is the only
 *    saturated colour on the page — see `--color-diff-add` — because a page
 *    whose product edits your files should spend its one colour there.
 * 3. Its turns carry a three-bar level meter driven by the same `meter`
 *    keyframe commandment's seven-bar meter uses. Deliberately the same motion
 *    word: the two apps are siblings and should move like it.
 * 4. Your turns carry a static waveform glyph rather than a second animation.
 *    Two things pulsing at once reads as a loading state, not a conversation.
 *
 * No `motion` dependency: opacity, transform, and slicing two arrays. The frame
 * has fixed minimum heights sized to its tallest state, because a mock that
 * grows as rows arrive is the most likely source of layout shift on this page.
 */

const TURNS = [
  {
    text: "Why does the daemon socket fall back to a temp path?",
    who: "you",
  },
  {
    text: "The socket lives under Application Support. When that path is longer than a Unix socket allows, it hashes the workspace and uses TMPDIR instead. Want me to log which one it picked?",
    who: "duck",
  },
  {
    text: "Yes, but only when it falls back.",
    who: "you",
  },
] as const;

const ROWS = [
  { arg: '"daemon.sock"', tool: "grep_search" },
  { arg: "cli/src/constants.ts", tool: "read_file" },
  { arg: "cli/src/constants.ts", tool: "edit_file" },
] as const;

/** One context line, one addition, one context line. The addition is the only
 * thing on the page drawn in a hue. */
const DIFF = [
  { kind: "context", text: "  if (socketPath.length > MAX_UNIX_PATH) {" },
  { kind: "add", text: '+   logInfo("socket fallback to tmp");' },
  { kind: "context", text: "    return tmpSocketPath(id);" },
] as const;

/**
 * The loop, as data rather than as branches. `turns` and `rows` are counts, so
 * a step is read as "two turns spoken, one tool run" instead of being decoded
 * from four booleans.
 */
const FRAMES = [
  { diff: false, rows: 0, speaking: false, turns: 1 },
  { diff: false, rows: 1, speaking: false, turns: 1 },
  { diff: false, rows: 2, speaking: false, turns: 1 },
  { diff: false, rows: 2, speaking: true, turns: 2 },
  { diff: false, rows: 2, speaking: true, turns: 2 },
  { diff: false, rows: 2, speaking: false, turns: 3 },
  { diff: false, rows: 3, speaking: false, turns: 3 },
  { diff: true, rows: 3, speaking: false, turns: 3 },
  { diff: true, rows: 3, speaking: false, turns: 3 },
  { diff: true, rows: 3, speaking: false, turns: 3 },
] as const;

/** The frame the server renders, and the frame a reduced-motion reader is left
 * on: the edit made and the diff open. Never step 0 — the outcome is the thing
 * worth showing, not the empty state it starts from. */
const RESTING_STEP = 8;

const BAR_HEIGHTS = [55, 100, 70];

const WaveformGlyph = () => (
  <span
    aria-hidden="true"
    className="mt-1.5 flex h-3 shrink-0 items-center gap-[2px]"
  >
    {[40, 80, 55, 95, 45].map((height) => (
      <span
        className="w-[2px] rounded-full bg-ink-ghost"
        key={height}
        style={{ height: `${height}%` }}
      />
    ))}
  </span>
);

const LevelMeter = ({ active }: { active: boolean }) => (
  <span
    aria-hidden="true"
    className="mt-1.5 flex h-3 shrink-0 items-end gap-[2px]"
  >
    {BAR_HEIGHTS.map((height, index) => (
      <span
        className={cn(
          "w-[2px] origin-bottom rounded-full bg-ink-subtle",
          active && "animate-[meter_620ms_ease-in-out_infinite]"
        )}
        key={height}
        style={{ animationDelay: `${index * 70}ms`, height: `${height}%` }}
      />
    ))}
  </span>
);

export const SessionMock = () => {
  const { active, ref, step } = useMockClock({
    intervalMs: 550,
    reducedStep: RESTING_STEP,
    steps: FRAMES.length,
  });

  const frame = FRAMES[step] ?? FRAMES[RESTING_STEP];

  return (
    <div className="select-none" ref={ref}>
      {/* Menu bar. Right-aligned status items, the way the real one sits. */}
      <div className="flex items-center justify-end gap-3 border-white/5 border-b bg-surface-0/80 px-3 py-1.5">
        <span className="font-mono text-[10px] text-ink-subtle">
          ~/Code/rubber-duck
        </span>
        <LevelMeter active={active && frame.speaking} />
        <span className="font-mono text-[10px] text-ink-subtle tabular-nums">
          9:41
        </span>
      </div>

      <div className="grid gap-px bg-white/5 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        {/* Left: what was said. Fixed minimum height so the third turn arriving
            cannot push the frame open. */}
        <div className="min-h-[14.5rem] bg-surface-1 px-4 py-4 sm:min-h-[15rem]">
          <p className="font-medium text-[11px] text-ink-faint">Spoken</p>
          <ol className="mt-3 space-y-3">
            {TURNS.slice(0, frame.turns).map((turn, index) => (
              <li className="flex gap-2.5" key={turn.who + String(index)}>
                {turn.who === "you" ? (
                  <WaveformGlyph />
                ) : (
                  <LevelMeter
                    active={
                      active && frame.speaking && index === frame.turns - 1
                    }
                  />
                )}
                <p
                  className={cn(
                    "text-pretty text-[13px] leading-relaxed",
                    turn.who === "you" ? "text-ink" : "text-ink-muted"
                  )}
                >
                  {turn.text}
                </p>
              </li>
            ))}
          </ol>
        </div>

        {/* Right: what it did about it. */}
        <div className="min-h-[14.5rem] bg-surface-1 px-4 py-4 sm:min-h-[15rem]">
          <p className="font-medium text-[11px] text-ink-faint">Tool ledger</p>
          <ol className="mt-3 space-y-2">
            {ROWS.slice(0, frame.rows).map((row, index) => (
              <li key={row.tool}>
                <div className="flex items-baseline gap-2 font-mono text-[11px]">
                  <span className="text-ink">{row.tool}</span>
                  <span className="truncate text-ink-faint">{row.arg}</span>
                </div>
                {index === ROWS.length - 1 && frame.diff ? (
                  <pre className="mt-2 overflow-hidden rounded-lg bg-surface-2 px-2.5 py-2 font-mono text-[10.5px] leading-relaxed">
                    <code>
                      {DIFF.map((line) => (
                        <span
                          className={cn(
                            "block",
                            line.kind === "add"
                              ? "-mx-2.5 bg-diff-add-bg px-2.5 text-diff-add"
                              : "text-ink-faint"
                          )}
                          key={line.text}
                        >
                          {line.text}
                        </span>
                      ))}
                    </code>
                  </pre>
                ) : null}
              </li>
            ))}
          </ol>
        </div>
      </div>
    </div>
  );
};
