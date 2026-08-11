import { Reveal } from "@/components/ui/reveal";
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
 * `id="vs-chat"` is deliberate and load-bearing. It was the anchor on an FAQ
 * entry — "How is this different from a chat window?" — whose answer was "it
 * can open the files you are asking about". That answer is now this table, so
 * the anchor moved with it rather than being deleted out from under every link
 * `faqSchema()` ever published.
 */
export const ToolsTable = () => (
  <Section id="vs-chat">
    <Container>
      <Reveal>
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
        <p className="mt-8 max-w-[60ch] text-ink-faint text-sm" id="tools-note">
          Every row checked against{" "}
          <a
            className="text-ink underline decoration-white/25 underline-offset-4 hover:decoration-white/60 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2"
            href={`${siteConfig.links.github}/blob/main/${TOOLS.source}`}
          >
            {TOOLS.source}
          </a>
          , which is the file that executes them.
        </p>

        <section
          aria-describedby="tools-note"
          aria-label="The seven tools and their safe mode behaviour"
          className="-mx-4 mt-4 overflow-x-auto px-4 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2 sm:mx-0 sm:px-0"
          // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-reachable — WCAG 2.1 G202.
          tabIndex={0}
        >
          <table className="w-full min-w-[38rem] border-collapse text-left text-sm">
            <caption className="sr-only">
              The seven voice tools, what each does, and which are refused in
              safe mode
            </caption>
            <thead>
              <tr className="border-white/10 border-b">
                <th className="py-3 pr-4 font-medium text-ink" scope="col">
                  Tool
                </th>
                <th
                  className="py-3 pr-4 font-medium text-ink-muted"
                  scope="col"
                >
                  What it does
                </th>
                <th className="py-3 font-medium text-ink-muted" scope="col">
                  In safe mode
                </th>
              </tr>
            </thead>
            <tbody>
              {TOOLS.rows.map((tool) => (
                <tr className="border-white/5 border-b" key={tool.name}>
                  <th
                    className="sticky left-0 z-10 whitespace-nowrap bg-canvas py-3 pr-4 font-medium font-mono text-ink text-xs"
                    scope="row"
                  >
                    {tool.name}
                  </th>
                  <td className="text-pretty py-3 pr-4 text-ink-muted">
                    {tool.does}
                  </td>
                  <td className="whitespace-nowrap py-3 text-ink">
                    {tool.safe}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <p className="mt-6 max-w-[65ch] text-pretty text-ink-faint text-sm">
          The safe mode shell allowlist, in full: {TOOLS.allowlist}. Anything
          else is refused before it runs.
        </p>
      </Reveal>
    </Container>
  </Section>
);
