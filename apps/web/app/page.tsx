import { AnswerBlock } from "@/components/marketing/answer-block";
import { ClosingCta } from "@/components/marketing/closing-cta";
import { FactList } from "@/components/marketing/fact-list";
import { Hero } from "@/components/marketing/hero";
import { ProseSection } from "@/components/marketing/prose-section";
import { ToolsTable } from "@/components/marketing/tools-table";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { BARGE_IN, CODE_ACCESS, PROOF } from "@/lib/content";
import { getLatestRelease } from "@/lib/release";

/**
 * Section order, and why it is this order.
 *
 * Claim, then the answer to "what is this", then the two questions that decide
 * whether somebody installs it — what it can do to their files, and whether
 * they can stop it talking — then where the code is read, then proof, then the
 * ask.
 *
 * There is no problem section between the answer and the tools, and its absence
 * is the decision: a reader who searched for a voice coding tool already has
 * the problem, so a screen spent describing it back to them is a screen they
 * scroll past to reach the table below.
 *
 * The tool table sits second from the top on purpose. It is the most alarming
 * thing on the page and also the most convincing, and burying it under the
 * next sections would read as hoping nobody scrolled that far. Proof sits
 * before the closing CTA rather than after it: a reader who has decided does
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
    <div className="isolate flex min-h-dvh flex-col overflow-clip bg-canvas font-sans">
      <SiteHeader />

      <main className="flex-1">
        <Hero downloadUrl={downloadUrl} fileSizeMB={fileSizeMB} />

        <AnswerBlock />
        <ToolsTable />
        <div className="border-white/8 border-y">
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
        </div>
        <FactList facts={PROOF.rows} heading={PROOF.heading} id="proof" />
        <ClosingCta downloadUrl={downloadUrl} version={version} />
      </main>

      <SiteFooter version={version} />
    </div>
  );
}
