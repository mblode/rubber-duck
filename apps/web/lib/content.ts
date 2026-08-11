import { siteConfig } from "@/lib/config";

/**
 * Every word on the page that is not markup lives here.
 *
 * Two reasons, both of which have already cost somebody an afternoon somewhere
 * in this fleet. The first is that a claim in JSX cannot be asserted by a test,
 * so the answer paragraph drifts out of its word band and the FAQ stops matching
 * the JSON-LD and nobody notices until a rich result quietly stops appearing.
 * The second is that `dateModified` derived from a build clock claims every page
 * changed on every deploy, which is a freshness signal that means nothing.
 *
 * So: constants here, `lib/content.test.ts` holds them to their contracts, and
 * the page is markup.
 *
 * Every claim about the app in this file is traced to a file in this
 * repository, and the source is named in the comment above the constant. If a
 * sentence here cannot be checked against Swift or TypeScript that ships, it
 * does not belong in it.
 */

/**
 * The liftable answer. An answer engine will quote this paragraph or none, so it
 * has to stand alone with no antecedent — no "it", no "the app", no reference to
 * the headline above it.
 *
 * 40-60 words is the band, asserted in `lib/content.test.ts`. Under 40 and it
 * omits the qualifier that makes it true; over 60 and it gets truncated
 * mid-clause, which is worse than being short.
 */
export const ANSWER_QUESTION = "What is Rubber Duck?";

export const ANSWER_TEXT =
  "Rubber Duck is a free macOS menu bar app for talking through code out loud and hearing the answer back. Point duck at a repo and press Option+D. It reads files, greps, runs commands and makes edits on your machine through a local daemon, on your own OpenAI key.";

/** The macOS 15.2 and API key requirement is stated in the hero and again in the
 * closing CTA, both within a screen of a download button. A third copy here was
 * the same sentence a reader had already read. */
export const ANSWER_NOTE = "Free and MIT licensed.";

/**
 * Bumped when the answer, an FAQ answer, or a comparison claim changes. Not when
 * a class name moves.
 *
 * Hand-written rather than `new Date()` or a git mtime, and the reason is in
 * both of those alternatives: a build clock marks the page as changed on every
 * deploy, and an mtime marks it as changed when a formatter touches it. Three
 * surfaces read this one constant — the visible `<time>`, `WebPage.dateModified`
 * and `sitemap.ts` — so they cannot disagree with each other.
 */
export const PAGE_UPDATED = "2026-08-11";

export const PAGE_UPDATED_LABEL = "11 August 2026";

/** The fold. The h1 is a claim carrying the words somebody would search for; it
 * is deliberately not phrased as a question, because a page whose headline is a
 * typed query reads as bait to a human and gains nothing with a machine that is
 * already reading the h2 below it. */
export const HERO = {
  headline: "A voice coding agent for macOS that reads and edits your repo.",
  subhead:
    "Press Option+D and think out loud. It answers in speech and makes the edit on your machine.",
} as const;

/**
 * There is deliberately no problem section.
 *
 * It was two cards under "Why is explaining your code to a chat window so
 * slow?", and it was the most skippable block on the page: somebody who
 * searched for a voice coding tool arrived because they already have the
 * problem, and naming it back at them spends a screen to tell them something
 * they came here knowing. Neither reference site for this design carries one.
 *
 * Its lede was the only place the page explained rubber duck debugging itself.
 * That premise was not lost with it — the "What is rubber duck debugging?" FAQ
 * entry states it more precisely, naming The Pragmatic Programmer rather than
 * gesturing at "it predates every model", and carrying the same claim that
 * describing what the code should do next to what it does is what exposes the
 * mismatch.
 *
 * One argument did not survive it, and was moved rather than dropped. The cards
 * carried the pasting tax — that you write the question twice, once to work out
 * what you are confused about and again into the box with the file underneath —
 * and the comparison table does not make that argument, because a plain text
 * chat window is not one of its four columns. It is now the fourth sentence of
 * `COMPARISON.honesty`, which is the paragraph that already reasons about when
 * to use what.
 *
 * What was deliberately not moved: "by then you have let go of the thread" and
 * "the answers get longer without getting closer". Neither is checkable — one
 * is a claim about the reader's attention and the other is a swipe at output
 * quality — and this page does not keep claims it cannot source. The cards'
 * other half, that a chat window answers about code it was told about rather
 * than code it read, is already carried as a capability fact by the "Reads and
 * edits files on your machine" row and by the tool table itself.
 */

/**
 * The seven tools.
 *
 * This is the most quotable block on the page and no competing product
 * publishes an equivalent, so every row is checked against source rather than
 * described from memory. The names and descriptions come from the tool schemas
 * the model is actually handed in `apps/macos/Tools/ToolDefinitions.swift`; the
 * limits and the safe-mode column come from the dispatcher that executes them
 * in `cli/src/daemon/voice-tools.ts`.
 *
 * `safe` is written as prose rather than a tick, because two of the three
 * answers are not "yes" or "no": `bash` is neither refused nor unrestricted,
 * and saying so is the point of the column.
 *
 * Every number in a `does` cell is load-bearing and survived the cut: the 1 MB
 * read ceiling, the 30 second kill, the 100 KB output cap, the 200 result stop.
 * They are what make the row checkable rather than a claim.
 *
 * The last sentence of `body` came from the deleted `duck` command table, whose
 * lede was the only place the page said that every call and edit is written to
 * the terminal as it happens. The five subcommands went with the table — the
 * README and `duck --help` are the contract for those — but this is a fact about
 * what the agent does to your repo and it belongs next to the tools.
 */
export const TOOLS = {
  allowlist:
    "git · grep · rg · find · ls · cat · head · tail · wc · swift test · xcodebuild test · npm test · pytest",
  body: "Seven local tools, scoped to the attached workspace; paths outside it are refused. Every call and edit streams into the duck terminal.",
  heading: "What can it actually do to my code?",
  rows: [
    {
      does: "One file, up to 1 MB.",
      name: "read_file",
      safe: "Allowed",
    },
    {
      does: "Creates or overwrites, making parent directories.",
      name: "write_file",
      safe: "Refused",
    },
    {
      does: "Replaces one exact block, refusing text that is missing or repeated.",
      name: "edit_file",
      safe: "Refused",
    },
    {
      does: "A shell command, killed at 30 seconds, output cut at 100 KB.",
      name: "bash",
      safe: "Allowlist only",
    },
    {
      does: "Greps recursively, optionally filtered to a glob.",
      name: "grep_search",
      safe: "Allowed",
    },
    {
      does: "Matches a glob, skipping .git, .build and node_modules, stopping at 200 results.",
      name: "find_files",
      safe: "Allowed",
    },
    {
      does: "Queries Exa, once you set an Exa API key.",
      name: "web_search",
      safe: "Allowed",
    },
  ],
  /** Moved out of `body` so the toggle sits with the allowlist it controls,
   * rather than being asserted once above the table and again below it. */
  safeMode:
    "Safe mode is a Settings toggle, off by default. It refuses write_file and edit_file, and the shell drops to:",
  source: "cli/src/daemon/voice-tools.ts",
} as const;

/**
 * Barge-in, from `docs/barge-in-architecture.md` and the coordinator it
 * describes. The guard windows and the confirmation delay are the two details
 * worth stating: without them "you can interrupt it" describes a microphone
 * that cuts the reply off every time the speaker plays a consonant.
 */
export const BARGE_IN = {
  body: "Yes. Speak while it answers and playback stops at the word you heard. An echo guard and confirmation delay stop its own voice or a cough from interrupting. Auto-abort is on by default and can be disabled in Settings.",
  heading: "Can I interrupt it mid-sentence?",
} as const;

/**
 * There is deliberately no `duck` command table.
 *
 * It was five subcommands — `duck [path]`, `say`, `sessions`, `doctor`,
 * `remote` — and it was reference material on a page that has to sell the idea
 * first. The CLI's own `--help` and the README table are the contract for those
 * five, and a description improved here and nowhere else is a description that
 * is wrong in one of the two places somebody reads it.
 *
 * What a landing page needs of the CLI is the one command that starts it, and
 * that is now `DUCK_COMMAND` in the hero, directly under the brew line, so the
 * two steps read as the quickstart they are.
 *
 * Two facts were moved rather than dropped. The lede's claim that every call and
 * every edit streams into the terminal as it happens is now the last sentence of
 * `TOOLS.body`. That the daemon installs itself on first launch — which was the
 * "What if the daemon is not running?" FAQ answer — is now in `CODE_ACCESS`,
 * next to the daemon it describes.
 */
export const DUCK_COMMAND = "duck ~/Code/your-repo";

/**
 * The trust question, answered without hedging.
 *
 * The last sentence is the one that matters and it is the one a marketing page
 * would drop: `web_search` leaves the machine. Everything before it would read
 * as "nothing leaves your Mac", which is not true, and a reader who finds the
 * exception themselves discounts the rest of the paragraph with it.
 */
export const CODE_ACCESS = {
  body: "A local daemon reads and edits within the attached workspace and installs on first launch. There is no Rubber Duck server. Tool results return to OpenAI on your key, and web_search sends its query to Exa.",
  heading: "Where does my code get read?",
} as const;

/**
 * The comparison.
 *
 * Cursor is missing on purpose. Comparing a menu-bar agent to an editor is off
 * intent — the reader is not choosing between them, they are already in one.
 *
 * `COMPARED_ON` is not decoration, and one cell in this table is the reason:
 * Claude Code's price was read off claude.com/pricing on that date and nowhere
 * else. Re-read it before changing the date; never carry a competitor's price
 * forward on memory.
 *
 * There is no price cell for ChatGPT voice mode. openai.com returned 403 to
 * every attempt to read its pricing page on the check date, and the rule here
 * is that an unread price is left out rather than recalled — so the row asks
 * what each product requires of you, which is answerable for all four.
 */
export const COMPARED_ON = "11 August 2026";

export const COMPARISON = {
  columns: [
    "Rubber Duck",
    "Claude Code",
    "ChatGPT voice mode",
    "Dictation into an agent",
  ],
  heading: "How is this different from Claude Code and ChatGPT voice mode?",
  // Two paragraphs, not one. It was a 533-character block welding two separate
  // arguments together — the concession to Claude Code, and the pasting tax a
  // chat window charges — and a reader who was only weighing the first had to
  // walk through the second to reach the end of the sentence.
  //
  // The concession stays exactly as blunt as it was. A comparison with no losing
  // row reads as marketing and gets discounted entirely, including the rows that
  // were true. The pasting argument stays too: the rows compare four products
  // and a plain text chat window is not one of them, so nothing else on the page
  // says what a chat window costs you to use.
  honesty: [
    "Rubber Duck is a worse coding agent than Claude Code and is not trying to be one. Claude Code plans across a repo and writes the patch. Rubber Duck answers what you asked out loud and makes the one edit that follows.",
    "Against a chat window the difference is the pasting: you write the question twice, once to work it out and again into the box with the file underneath.",
  ],
  rows: [
    {
      label: "How you talk to it",
      values: [
        "Speak, it speaks back",
        "Type in a terminal",
        "Speak, it speaks back",
        "Speak, the words are typed",
      ],
    },
    {
      label: "Reads and edits files on your machine",
      values: [
        "Yes, via a local daemon",
        "Yes",
        "No",
        "Yes, whichever agent you dictated into",
      ],
    },
    {
      label: "Hear the answer out loud",
      values: ["Yes", "No", "Yes", "No"],
    },
    {
      label: "What it requires",
      values: [
        // "Billed per minute of audio" moved here from the deleted cost FAQ.
        "An OpenAI API key, billed per minute of audio. No account, no subscription",
        // Both halves of "a subscription, Pro is $20" were true and the cell was
        // still misleading: Anthropic's own Claude Code FAQ documents Console
        // billing at standard API rates, which is the same bring-your-own-key
        // model this page sells as its differentiator one column to the left.
        // Omitting it was the one place this table overstated our advantage.
        // Checked 11 Aug 2026.
        "A subscription or an API key billed per token, not the free tier. Pro is $20 a month",
        "A ChatGPT account",
        "Whatever each half requires",
      ],
    },
    {
      label: "Source code",
      values: ["MIT on GitHub", "Closed", "Closed", "Varies"],
    },
  ],
} as const;

/**
 * Proof.
 *
 * Every row is a fact somebody can check, and every row carries the link they
 * would check it with. There are no stars, no download counts and no
 * testimonials here, and that is a decision rather than an omission: this
 * project has two GitHub stars, and a page that renders "2" next to a download
 * button has spent its credibility to say nothing.
 *
 * Note what is NOT claimed. The app is notarised but it is *not* sandboxed —
 * `apps/macos/RubberDuck.entitlements` grants network client and server access
 * and carries no `com.apple.security.app-sandbox` key. "Sandboxed and notarised"
 * would have been one word of polish and one false statement.
 *
 * The iPhone row is here rather than in the FAQ because there is nothing to
 * answer: an FAQ entry about an app you cannot install is an announcement
 * dressed as a question.
 */
const REPO = siteConfig.links.github;

/**
 * The "Tools" row is gone and its link went to the tool table's own sourcing
 * note, which points at the same `voice-tools.ts`. All three of its claims —
 * seven tools, two refused in safe mode, the shell dropped to an allowlist —
 * are the section three above this one, stated at length. A fact list that
 * repeats a table earns nothing and costs a row.
 */
export const PROOF = {
  closing:
    "Built by one person in Melbourne. No case studies and no customer logos, because there is no roster yet.",
  heading: "What is shipped today?",
  rows: [
    {
      detail: "MIT. Read, fork and ship it.",
      href: `${REPO}/blob/main/LICENSE.md`,
      term: "Licence",
    },
    {
      detail:
        "Developer ID signed and notarised by Apple on every tagged release. Not sandboxed.",
      href: `${REPO}/blob/main/.github/workflows/release.yml`,
      term: "Notarised",
    },
    {
      detail:
        "Your OpenAI key lives in the macOS Keychain, never a config file, and stays there after you uninstall.",
      href: `${REPO}/blob/main/apps/macos/KeychainManager.swift`,
      term: "Key storage",
    },
    {
      detail:
        "24 kHz mono, streamed to the OpenAI Realtime API and answered by gpt-realtime-1.5.",
      href: `${REPO}/blob/main/apps/macos/RealtimeClient.swift`,
      term: "Audio path",
    },
    {
      detail:
        "Option+D starts the agent, Option+Shift+D opens Settings. Both rebind.",
      href: `${REPO}/blob/main/apps/macos/HotkeyManager.swift`,
      term: "Default shortcuts",
    },
    {
      detail: "macOS 15.2 or later, on Apple silicon or Intel.",
      href: `${REPO}/releases/latest`,
      term: "Requirements",
    },
    {
      detail:
        "An iPhone app exists in the repository, but it is not on TestFlight or the App Store yet.",
      href: `${REPO}/tree/main/apps/ios`,
      term: "iPhone",
    },
  ],
} as const;

export const FAQ_HEADING = "What do people ask before installing?";

export const CLOSING = {
  heading: "Ready to talk through it instead?",
  lede: "Free, MIT licensed, on your own OpenAI key. Say the next thing out loud instead of pasting it.",
} as const;

export const BREW_COMMAND = "brew install --cask mblode/tap/rubber-duck";
