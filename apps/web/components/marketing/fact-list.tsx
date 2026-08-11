import { Container, Section, SectionHeading } from "@/components/ui/section";

interface Fact {
  detail: string;
  href: string;
  linkLabel: string;
  term: string;
}

/**
 * Proof, as a list of things somebody can go and verify.
 *
 * What is not here matters more than what is. No star count, no download total,
 * no testimonials, no logo wall. This project has two GitHub stars; a page that
 * renders "2" beside a download button has spent real credibility to say
 * nothing, and diffhub deleted its own star count for exactly that reason — a
 * release count is a signal about a project, not an answer about a product.
 *
 * So every row is a fact with a link, and the closing line says out loud that
 * there is no customer roster yet. A reader who checks two of these and finds
 * them true will believe the third. A reader who finds a padded number will not
 * check anything else on the page.
 */
export const FactList = ({
  facts,
  heading,
  id,
}: {
  facts: readonly Fact[];
  heading: string;
  id?: string;
}) => (
  <Section id={id}>
    <Container>
      <SectionHeading>{heading}</SectionHeading>
      <dl className="mt-14 grid border-white/10 border-t md:grid-cols-2">
        {facts.map((fact) => (
          <div
            className="border-white/10 border-b py-6 md:p-7 md:[&:nth-child(even)]:pr-0 md:[&:nth-child(odd)]:border-r md:[&:nth-child(odd)]:pl-0"
            key={fact.term}
          >
            <dt className="font-mono text-duck text-sm">{fact.term}</dt>
            <dd className="mt-4 max-w-[46ch] text-pretty text-ink-muted">
              {fact.detail}{" "}
              <a
                className="whitespace-nowrap text-ink underline decoration-white/25 underline-offset-4 hover:decoration-white/60 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2"
                href={fact.href}
              >
                {fact.linkLabel}
              </a>
            </dd>
          </div>
        ))}
      </dl>
    </Container>
  </Section>
);
