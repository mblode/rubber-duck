import { Reveal } from "@/components/ui/reveal";
import { Container, Section, SectionHeading } from "@/components/ui/section";

/**
 * A question and its answer, with nothing around it.
 *
 * The two questions that stop an install — whether it can interrupt itself when
 * you talk over it, and where your code is actually read — are each one honest
 * paragraph. Both were briefly diagrams, and both versions said less than the
 * sentence does: a three-node flow chart of "mic → app → OpenAI" is a picture
 * of a sentence, and a reader deciding whether to trust this with a repo is
 * reading, not scanning. So there is no graphic here on purpose.
 */
export const ProseSection = ({
  body,
  heading,
  id,
}: {
  body: string;
  heading: string;
  id?: string;
}) => (
  <Section id={id}>
    <Container>
      <Reveal>
        <SectionHeading>{heading}</SectionHeading>
        <p className="mt-4 max-w-[65ch] text-pretty text-ink-muted text-lg leading-relaxed">
          {body}
        </p>
      </Reveal>
    </Container>
  </Section>
);
