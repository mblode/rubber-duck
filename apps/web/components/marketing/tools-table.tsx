import { Container, Section, SectionHeading } from "@/components/ui/section";
import { siteConfig } from "@/lib/config";
import { TOOLS } from "@/lib/content";

/**
 * The seven tools, as a real `<table>`.
 *
 * This is the most quotable block on the page. No competing voice product
 * publishes the list of things its agent is allowed to do to your disk, which
 * means this table is the one piece of the page an answer engine cannot get
 * from anybody else — and that is exactly why it has to be right. Every row is
 * checked against `cli/src/daemon/voice-tools.ts` and the tool schemas in
 * `apps/macos/Tools/ToolDefinitions.swift`; the caption links to the first so a
 * reader can do the same check in one click.
 *
 * A real table rather than a grid of divs, because `<th scope>` is what lets a
 * machine say "edit_file: refused in safe mode" instead of reading a column of
 * orphaned strings.
 *
 * `id="vs-chat"` preserves existing deep links to this explanation.
 */
export const ToolsTable = () => (
  <Section className="border-white/8 border-y" id="vs-chat">
    <Container>
      <SectionHeading lede={TOOLS.body}>{TOOLS.heading}</SectionHeading>

      {/* A labelled landmark with a tab stop: the WCAG-documented pattern for
            a scrollable area, and all three parts are load-bearing. Without the
            tab stop a keyboard user cannot pan the table and simply loses the
            safe-mode column on a phone. Without the accessible name the focus
            stop is a dead end with nothing announced. The lint rule is guarding
            against a stray tab stop on an anonymous `<div>`, which this is not. */}
      {/* Outside the scroller: as a `<caption>` this inherited the
            table's min-width, so on a 390px phone it rendered ~700px wide
            and clipped mid-word, taking its sourcing detail off-screen. */}
      <p className="mt-14 max-w-[60ch] text-ink-faint text-sm" id="tools-note">
        Tool code:{" "}
        <a
          className="text-ink underline decoration-white/25 underline-offset-4 hover:decoration-white/60 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2"
          href={`${siteConfig.links.github}/blob/main/${TOOLS.source}`}
        >
          {TOOLS.source}
        </a>
        .
      </p>

      <section
        aria-describedby="tools-note"
        aria-label="Seven tools and what safe mode allows"
        className="-mx-5 mt-6 overflow-x-auto px-5 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2 sm:-mx-8 sm:px-8"
        // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-reachable — WCAG 2.1 G202.
        tabIndex={0}
      >
        <table className="w-full min-w-[48rem] border-collapse text-left">
          <caption className="sr-only">
            Seven tools and what safe mode allows
          </caption>
          <thead>
            <tr className="border-white/15 border-b">
              <th
                className="whitespace-nowrap py-4 pr-8 font-mono font-normal text-ink-faint text-xs"
                scope="col"
              >
                Tool
              </th>
              <th
                className="whitespace-nowrap py-4 pr-8 font-mono font-normal text-ink-faint text-xs"
                scope="col"
              >
                What it does
              </th>
              <th
                className="whitespace-nowrap py-4 font-mono font-normal text-ink-faint text-xs"
                scope="col"
              >
                Safe mode
              </th>
            </tr>
          </thead>
          <tbody>
            {TOOLS.rows.map((tool) => (
              <tr className="border-white/8 border-b" key={tool.name}>
                <th
                  className="sticky left-0 z-10 whitespace-nowrap bg-canvas py-5 pr-8 font-medium font-mono text-duck text-sm"
                  scope="row"
                >
                  {tool.name}
                </th>
                <td className="max-w-[52ch] text-pretty py-5 pr-8 text-ink-muted">
                  {tool.does}
                </td>
                <td className="whitespace-nowrap py-5 font-mono text-ink text-sm">
                  {tool.safe}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <p className="mt-6 max-w-[65ch] text-pretty text-ink-faint text-sm">
        Safe mode allows these commands: {TOOLS.allowlist}. Everything else is
        blocked.
      </p>
    </Container>
  </Section>
);
