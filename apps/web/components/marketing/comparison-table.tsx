import { Reveal } from "@/components/ui/reveal";
import { Container, Section, SectionHeading } from "@/components/ui/section";
import { COMPARED_ON, COMPARISON } from "@/lib/content";

/**
 * The comparison, as a real `<table>`.
 *
 * A real table rather than a grid of divs, because this is the block most likely
 * to be quoted by something that is not a browser: `<th scope>` is what lets a
 * machine say "Commandment: free app, you pay OpenAI per second" instead of
 * reading a column of orphaned strings. The `<caption>` carries the date, which
 * is the difference between a claim and a checked claim.
 *
 * The honesty paragraph underneath is not a hedge and should not be softened. It
 * says out loud that Claude Code is the better coding agent, and the reason it
 * is here is selfish as well as honest: a comparison with no losing row reads
 * as marketing and gets discounted entirely, including the rows that were true.
 *
 * One cell in this table is a competitor's price and it was read off
 * claude.com/pricing on the checked-on date. There is no price cell for ChatGPT
 * voice mode because openai.com would not serve its pricing page to the check —
 * an unread price is left out, never recalled.
 *
 * Scrolls horizontally on narrow viewports, with `tabindex` so a keyboard user
 * can actually reach the scroll — a scrollable region that only a mouse can pan
 * is a common way to lose the last two columns on a phone.
 */
export const ComparisonTable = () => (
  <Section id="comparison">
    <Container>
      <Reveal>
        <SectionHeading>{COMPARISON.heading}</SectionHeading>

        {/* A labelled landmark with a tab stop: the WCAG-documented pattern for
            a scrollable area, and all three parts are load-bearing. Without the
            tab stop a keyboard user cannot pan the table and simply loses the
            last two columns on a phone. Without the accessible name the focus
            stop is a dead end with nothing announced. The lint rule is guarding
            against a stray tab stop on an anonymous `<div>`, which this is not. */}
        {/* Outside the scroller: as a `<caption>` this inherited the
            table's min-width, so on a 390px phone it rendered ~700px wide
            and clipped mid-word, taking its sourcing detail off-screen. */}
        <p
          className="mt-8 max-w-[60ch] text-ink-faint text-sm"
          id="comparison-note"
        >
          Checked against each product&rsquo;s public pricing and feature pages
          on {COMPARED_ON}. These ship often, so check before deciding.
        </p>

        <section
          aria-describedby="comparison-note"
          aria-label="Feature and pricing comparison"
          className="-mx-4 mt-4 overflow-x-auto px-4 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2 sm:mx-0 sm:px-0"
          // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-reachable — WCAG 2.1 G202.
          tabIndex={0}
        >
          <table className="w-full min-w-[44rem] border-collapse text-left text-sm">
            <caption className="sr-only">
              How Rubber Duck compares to Claude Code and ChatGPT voice mode
            </caption>
            <thead>
              <tr className="border-white/10 border-b">
                <td className="sticky left-0 z-10 bg-canvas py-3 pr-4" />
                {COMPARISON.columns.map((column, index) => (
                  <th
                    className={
                      index === 0
                        ? "py-3 pr-4 font-medium text-ink"
                        : "py-3 pr-4 font-medium text-ink-muted"
                    }
                    key={column}
                    scope="col"
                  >
                    {column}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {COMPARISON.rows.map((row) => (
                <tr className="border-white/5 border-b" key={row.label}>
                  <th
                    className="sticky left-0 z-10 bg-canvas py-3 pr-4 font-medium text-ink-subtle"
                    scope="row"
                  >
                    {row.label}
                  </th>
                  {row.values.map((value, index) => (
                    <td
                      className={
                        index === 0
                          ? "py-3 pr-4 text-ink"
                          : "py-3 pr-4 text-ink-muted"
                      }
                      key={`${row.label}-${COMPARISON.columns[index]}`}
                    >
                      {value}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <p className="mt-6 max-w-[65ch] text-pretty text-ink-muted">
          {COMPARISON.honesty}
        </p>
      </Reveal>
    </Container>
  </Section>
);
