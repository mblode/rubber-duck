import { siteConfig } from "@/lib/config";

/**
 * Every word on the page that is not markup lives here.
 *
 * Two reasons, both of which have already cost somebody an afternoon somewhere
 * in this fleet. The first is that a claim in JSX cannot be asserted by a test,
 * so the answer paragraph drifts out of its word band and the FAQ stops matching
 * its surrounding markup and nobody notices until the page ships.
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
export const ANSWER_QUESTION = "No more typing it all out.";

export const ANSWER_TEXT =
  "Rubber Duck sits in your Mac’s menu bar. Point it at a repo, press Option+D, and talk. It reads the code, answers out loud, runs commands, and makes edits. It runs from your Mac with your own OpenAI key. There is no Rubber Duck account or subscription.";

/** The macOS 15.2 and API key requirement is stated in the hero and again in the
 * closing CTA, both within a screen of a download button. A third copy here was
 * the same sentence a reader had already read. */
export const ANSWER_NOTE = "Free and open source.";

/**
 * Bumped when a published product claim changes. Not when a class name moves.
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
  headline: "Think out loud.",
  highlight: "Fix the code.",
  subhead:
    "Press Option+D. Ask about the repo, hear the answer, and let Rubber Duck make the edit.",
} as const;

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
  body: "Rubber Duck works inside the repo you choose. You can see every step in the terminal.",
  heading: "What it can do",
  rows: [
    {
      does: "Reads one file, up to 1 MB.",
      name: "read_file",
      safe: "Available",
    },
    {
      does: "Creates or replaces a file.",
      name: "write_file",
      safe: "Blocked",
    },
    {
      does: "Changes one exact piece of text.",
      name: "edit_file",
      safe: "Blocked",
    },
    {
      does: "Runs a command for up to 30 seconds. Output stops at 100 KB.",
      name: "bash",
      safe: "Limited",
    },
    {
      does: "Searches text across the repo.",
      name: "grep_search",
      safe: "Available",
    },
    {
      does: "Finds up to 200 files by name or pattern.",
      name: "find_files",
      safe: "Available",
    },
    {
      does: "Searches the web through Exa. Needs an Exa key.",
      name: "web_search",
      safe: "Available",
    },
  ],
  source: "cli/src/daemon/voice-tools.ts",
} as const;

/**
 * Barge-in, from `docs/barge-in-architecture.md` and the coordinator it
 * describes. The guard windows and the confirmation delay are the two details
 * worth stating: without them "you can interrupt it" describes a microphone
 * that cuts the reply off every time the speaker plays a consonant.
 */
export const BARGE_IN = {
  body: "Start talking and Rubber Duck stops where you cut in. A short pause keeps echoes and coughs from cutting it off. You can turn this off in Settings.",
  heading: "Interrupt anytime",
} as const;

/**
 * The trust question, answered without hedging.
 *
 * The last sentence is the one that matters and it is the one a marketing page
 * would drop: `web_search` leaves the machine. Everything before it would read
 * as "nothing leaves your Mac", which is not true, and a reader who finds the
 * exception themselves discounts the rest of the paragraph with it.
 */
export const CODE_ACCESS = {
  body: "Rubber Duck reads and edits the repo on your Mac. Tool results go to OpenAI using your key. Web searches go to Exa. There is no Rubber Duck server.",
  heading: "Where your code goes",
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
  heading: "Before you install",
  rows: [
    {
      detail: "MIT licensed. Read it, fork it, change it.",
      href: `${REPO}/blob/main/LICENSE.md`,
      linkLabel: "View licence",
      term: "Source",
    },
    {
      detail:
        "Apple signs and notarises each release. The app is not sandboxed.",
      href: `${REPO}/blob/main/.github/workflows/release.yml`,
      linkLabel: "View builds",
      term: "Apple",
    },
    {
      detail:
        "Your OpenAI key stays in Keychain, even after you uninstall the app.",
      href: `${REPO}/blob/main/apps/macos/KeychainManager.swift`,
      linkLabel: "View code",
      term: "Your key",
    },
    {
      detail: "Works on macOS 15.2 or newer, on Apple silicon or Intel.",
      href: `${REPO}/releases/latest`,
      linkLabel: "View releases",
      term: "Mac",
    },
  ],
} as const;

export const CLOSING = {
  heading: "Start talking.",
  lede: "Download Rubber Duck for macOS. It’s free and open source.",
} as const;
