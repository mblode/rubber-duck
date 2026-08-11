import { Container, Section } from "@/components/ui/section";

export const ProseSection = ({
  body,
  heading,
  id,
}: {
  body: string;
  heading: string;
  id?: string;
}) => (
  <Section
    className="border-white/8 border-t py-16 first:border-t-0 sm:py-20"
    id={id}
  >
    <Container>
      <div className="grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(20rem,3fr)] lg:gap-20">
        <h2 className="max-w-[20ch] text-balance font-medium text-3xl text-ink tracking-[-0.035em] sm:text-4xl">
          {heading}
        </h2>
        <p className="max-w-[58ch] text-pretty text-ink-muted text-lg lg:pt-1">
          {body}
        </p>
      </div>
    </Container>
  </Section>
);
