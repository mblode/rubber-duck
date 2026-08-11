import { FaqSection } from "@/components/faq-section";
import { AnswerBlock } from "@/components/marketing/answer-block";
import { ClosingCta } from "@/components/marketing/closing-cta";
import { ComparisonTable } from "@/components/marketing/comparison-table";
import { Hero } from "@/components/marketing/hero";
import { ProseSection } from "@/components/marketing/prose-section";
import { ToolsTable } from "@/components/marketing/tools-table";
import { SiteFooter } from "@/components/site-footer";
import { Container } from "@/components/ui/section";
import { ZoneBreadcrumb } from "@/components/zone-breadcrumb";
import { siteConfig } from "@/lib/config";
import { BARGE_IN, CODE_ACCESS } from "@/lib/content";
import { getLatestRelease } from "@/lib/release";

/**
 * Section order, and why it is this order.
 *
 * Claim, then the answer to "what is this", then the two questions that decide
 * whether somebody installs it — what it can do to their files, and whether
 * they can stop it talking — then the CLI, then where the code is read, then
 * the comparison, then proof, then the questions, then the ask.
 *
 * There is no problem section between the answer and the tools, and its absence
 * is the decision: a reader who searched for a voice coding tool already has
 * the problem, so a screen spent describing it back to them is a screen they
 * scroll past to reach the table below.
 *
 * The tool table sits second from the top on purpose. It is the most alarming
 * thing on the page and also the most convincing, and burying it under the
 * comparison would read as hoping nobody scrolled that far. Proof sits *before*
 * the closing CTA rather than after it: a reader who has already decided does
 * not need it, and a reader who has not will never see it below the button.
 *
 * Every `h2` on this page is a question somebody would type into a search box.
 * That is not a stylistic preference — it is what lets an answer engine lift a
 * self-contained answer from a section instead of guessing what the section was
 * about from a noun phrase.
 */
export default async function Page() {
  const { downloadUrl, fileSizeMB, version } = await getLatestRelease();

  return (
    <div className="isolate flex min-h-dvh flex-col bg-canvas font-sans">
      {/* Root page only, and matched word for word by the BreadcrumbList in
          lib/config.ts. Google treats a mismatch between the visible trail and
          the markup as an error, so the two change together. */}
      <Container className="flex items-center justify-between gap-4 pt-8">
        <ZoneBreadcrumb product="Rubber Duck" />

        {/*
          Kept, where Commandment has no equivalent. The two pages are otherwise
          deliberately the same shape, and this is the one place the products
          differ enough to justify diverging: Rubber Duck's buyer is a developer
          who will want to read `voice-tools.ts` before granting anything write
          access to their repo, and making them scroll ten sections to the
          footer for that is the wrong friction to add. The tool table links the
          same file, but this is above the fold.
        */}
        <a
          aria-label="View on GitHub"
          className="relative -mr-2 inline-flex size-9 shrink-0 items-center justify-center rounded-lg text-ink-subtle transition-colors hover:bg-white/8 hover:text-ink focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2"
          href={siteConfig.links.github}
          rel="noopener noreferrer"
          target="_blank"
        >
          {/*
            Inlined for the same reason as the Apple mark in the download
            button: one glyph, and the only icon package installed here draws
            GitHub as a thin outline that reads as a generic cat next to a solid
            brand mark.
          */}
          <svg
            aria-hidden="true"
            fill="currentColor"
            height="18"
            viewBox="0 0 24 24"
            width="18"
          >
            <path d="M12.0459 1.0001a10.9969 10.9969 0 0 0-3.4824 21.444c.5498.0917.7331-.2749.7331-.5498v-1.8328c-3.0241.6414-3.6656-1.4663-3.6656-1.4663-.5499-1.283-1.283-1.6495-1.283-1.6495-.9164-.6415.0917-.6415.0917-.6415 1.0996 0 1.7411 1.0997 1.7411 1.0997.9164 1.6495 2.566 1.1913 3.2075.9164.0916-.7332.3665-1.1914.7331-1.4663-2.4743-.2749-5.0403-1.1913-5.0403-5.4068 0-1.1913.4582-2.1994 1.0997-2.9325-.1832-.275-.4582-1.283.0917-2.6576 0 0 .9164-.275 3.0241 1.0997a10.54 10.54 0 0 1 5.4985 0c2.1077-1.3746 3.0241-1.0997 3.0241-1.0997.5499 1.3746.275 2.3827.0917 2.6576.7331.7331 1.0997 1.7412 1.0997 2.9325 0 4.2155-2.566 5.1319-5.0403 5.4068.3666.3666.7332 1.0081.7332 2.0161v3.0242c0 .2749.1832.6415.7331.5498a10.997 10.997 0 0 0 7.4284-12.1646 10.9966 10.9966 0 0 0-10.8191-9.2794" />
          </svg>
          {/*
            Widens the tap target to 48px on touch without changing the visual
            size or disturbing the row's layout. `pointer-fine:hidden` keeps it
            out of the way of a mouse, where 36px is already comfortable.
          */}
          <span
            aria-hidden="true"
            className="-translate-1/2 absolute top-1/2 left-1/2 pointer-fine:hidden size-[max(100%,3rem)]"
          />
        </a>
      </Container>

      <main className="flex-1">
        {/* The glow is a light source above the fold, not a wash behind the
            headline. Pointer-events-none and behind everything. */}
        <div className="relative">
          <div
            aria-hidden="true"
            className="hero-glow pointer-events-none absolute inset-x-0 top-0 -z-10 h-[36rem]"
          />
          <Hero
            downloadUrl={downloadUrl}
            fileSizeMB={fileSizeMB}
            version={version}
          />
        </div>

        <AnswerBlock />
        <ToolsTable />
        <ProseSection
          body={BARGE_IN.body}
          heading={BARGE_IN.heading}
          id="barge-in"
        />
        <ProseSection
          body={CODE_ACCESS.body}
          heading={CODE_ACCESS.heading}
          id="code-access"
        />
        <ComparisonTable />
        <FaqSection />
        <ClosingCta downloadUrl={downloadUrl} version={version} />
      </main>

      <SiteFooter version={version} />
    </div>
  );
}
