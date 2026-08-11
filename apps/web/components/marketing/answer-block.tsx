import { Container, Section } from "@/components/ui/section";
import { ANSWER_NOTE, ANSWER_QUESTION, ANSWER_TEXT } from "@/lib/content";

export const AnswerBlock = () => (
  <Section className="py-16 sm:py-20">
    <Container>
      <div className="grid gap-5 lg:grid-cols-[minmax(12rem,1fr)_minmax(0,3fr)] lg:gap-16">
        <h2 className="font-mono text-duck text-sm">{ANSWER_QUESTION}</h2>
        <div>
          <p className="max-w-[62ch] text-pretty text-ink-muted text-lg">
            {ANSWER_TEXT}
          </p>
          <p className="mt-4 font-mono text-ink-faint text-sm">{ANSWER_NOTE}</p>
        </div>
      </div>
    </Container>
  </Section>
);
