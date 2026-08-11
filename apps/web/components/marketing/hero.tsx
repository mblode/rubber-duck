import { DownloadButton } from "@/components/marketing/download-button";
import { SessionTrace } from "@/components/mocks/session-trace";
import { Container } from "@/components/ui/section";
import { HERO } from "@/lib/content";

export const Hero = ({
  downloadUrl,
  fileSizeMB,
}: {
  downloadUrl: string;
  fileSizeMB: string;
}) => (
  <section className="border-white/8 border-b">
    <Container className="pt-12 pb-16 sm:pt-20 sm:pb-24">
      <div className="grid items-end gap-10 lg:grid-cols-[minmax(0,5fr)_minmax(18rem,2fr)] lg:gap-16">
        <div>
          <p className="font-mono text-ink-muted text-sm">
            Rubber Duck · macOS
          </p>
          <h1 className="mt-6 max-w-[10ch] text-balance font-medium text-6xl text-ink leading-[0.92] tracking-[-0.055em] sm:text-8xl lg:text-9xl">
            {HERO.headline}
            <span className="block text-duck">{HERO.highlight}</span>
          </h1>
        </div>

        <div className="flex flex-col items-start gap-6 lg:pb-2">
          <p className="max-w-[40ch] text-pretty text-ink-muted text-lg">
            {HERO.subhead}
          </p>

          <div className="flex flex-wrap items-center gap-4">
            <DownloadButton href={downloadUrl} />
            {fileSizeMB ? (
              <p className="font-mono text-ink-faint text-sm tabular-nums">
                {fileSizeMB}
              </p>
            ) : null}
          </div>

          <p className="max-w-[36ch] text-pretty text-ink-faint text-sm">
            Free · macOS 15.2+ · OpenAI key needed
          </p>
        </div>
      </div>

      <SessionTrace />
    </Container>
  </section>
);
