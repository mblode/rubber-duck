import { DownloadButton } from "@/components/marketing/download-button";
import { Container } from "@/components/ui/section";
import { CLOSING, PAGE_UPDATED, PAGE_UPDATED_LABEL } from "@/lib/content";

export const ClosingCta = ({
  downloadUrl,
  version,
}: {
  downloadUrl: string;
  version: string;
}) => (
  <section className="bg-duck py-20 text-canvas sm:py-24">
    <Container>
      <div className="flex flex-col items-start justify-between gap-10 lg:flex-row lg:items-end">
        <div>
          <h2 className="max-w-[22ch] text-balance font-medium text-4xl tracking-[-0.04em] sm:text-5xl">
            {CLOSING.heading}
          </h2>
          <p className="mt-5 max-w-[44ch] text-pretty text-canvas/75 text-lg">
            {CLOSING.lede}
          </p>
        </div>
        <div className="shrink-0">
          <DownloadButton
            className="bg-canvas text-ink hover:bg-surface-2 focus-visible:outline-canvas active:bg-surface-3"
            href={downloadUrl}
          />
          <p className="mt-4 font-mono text-canvas/60 text-xs tabular-nums">
            {version ? `${version} · ` : ""}macOS 15.2+ · Updated{" "}
            <time dateTime={PAGE_UPDATED}>{PAGE_UPDATED_LABEL}</time>
          </p>
        </div>
      </div>
    </Container>
  </section>
);
