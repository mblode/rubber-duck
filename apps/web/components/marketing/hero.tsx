import Image from "next/image";
import { DownloadButton } from "@/components/marketing/download-button";
import { ProductFrame } from "@/components/mocks/product-frame";
import { SessionMock } from "@/components/mocks/session-mock";
import { Container } from "@/components/ui/section";
import { BREW_COMMAND, DUCK_COMMAND, HERO } from "@/lib/content";

/**
 * The fold.
 *
 * The h1 carries no entrance animation, and that is a rule rather than an
 * oversight. It is the LCP element on this page: an animation that starts it at
 * `opacity: 0` moves the largest contentful paint to the end of the animation,
 * so the page measures slower for the sake of an effect nobody scrolled past yet
 * to see. The delay ladder starts at the subhead.
 *
 * One action, once. A second button here — "View on GitHub", "Read the docs" —
 * splits the decision at the exact moment the reader has made it.
 */
export const Hero = ({
  downloadUrl,
  fileSizeMB,
  version,
}: {
  downloadUrl: string;
  fileSizeMB: string;
  version: string;
}) => (
  <Container className="pt-10 pb-16 sm:pt-14 sm:pb-24">
    <div className="max-w-[46ch]">
      <Image
        alt=""
        className="rounded-[22%]"
        height={72}
        priority
        src="/rubber-duck/app-icon.png"
        width={72}
      />

      <h1 className="mt-6 max-w-[24ch] text-balance font-semibold text-4xl text-ink tracking-tight sm:text-5xl sm:tracking-[-0.03em]">
        {HERO.headline}
      </h1>

      <p className="mt-5 max-w-[50ch] text-pretty text-ink-muted text-lg blur-up [animation-delay:80ms]">
        {HERO.subhead}
      </p>

      <div className="mt-8 flex flex-wrap items-center gap-3.5 blur-up [animation-delay:160ms]">
        <DownloadButton href={downloadUrl} />
        {fileSizeMB ? (
          <p className="text-ink-faint text-sm">{fileSizeMB}</p>
        ) : null}
      </div>

      <p className="mt-3 text-ink-faint text-sm blur-up [animation-delay:240ms]">
        {version ? `${version} · ` : ""}Requires macOS 15.2 and an OpenAI API
        key
      </p>

      <code className="mt-4 block w-fit max-w-full overflow-x-auto rounded-lg bg-surface-1 px-3 py-2 font-mono text-ink-muted text-xs blur-up [animation-delay:240ms] sm:text-sm">
        {BREW_COMMAND}
      </code>
      <code className="mt-2 block w-fit max-w-full overflow-x-auto rounded-lg bg-surface-1 px-3 py-2 font-mono text-ink-muted text-xs blur-up [animation-delay:240ms] sm:text-sm">
        {DUCK_COMMAND}
      </code>
    </div>

    {/* Below the copy, not beside it. The mock is the proof, but the claim and
        the button are what a visitor came for, and a two-column fold puts them
        in competition for the same first second. */}
    <ProductFrame
      caption="One spoken question, three tools, and the edit it made."
      className="mt-12 blur-up [animation-delay:350ms] sm:mt-16"
      description="A spoken debugging conversation beside the local tools it ran and a three-line diff of the resulting edit."
    >
      <SessionMock />
    </ProductFrame>
  </Container>
);
