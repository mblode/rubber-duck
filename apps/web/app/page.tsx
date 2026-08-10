import Image from "next/image";

import { FaqDisclosure } from "@/components/faq-disclosure";
import { SiteFooter } from "@/components/site-footer";
import { ZoneBreadcrumb } from "@/components/zone-breadcrumb";
import { siteConfig } from "@/lib/config";

// Shape of an unvalidated GitHub API response, so every field is optional. The
// fetch below guards each access; declaring them required would make those
// guards look redundant while the runtime payload could still omit them.
interface GitHubRelease {
  assets?: Array<{
    name: string;
    browser_download_url: string;
    size: number;
  }>;
  tag_name?: string;
}

/**
 * Where the download button points when no `.dmg` asset resolves. A real page
 * that lists every asset, rather than a link that goes nowhere.
 */
const RELEASES_URL = "https://github.com/mblode/rubber-duck/releases/latest";

async function getLatestRelease() {
  try {
    const res = await fetch(
      "https://api.github.com/repos/mblode/rubber-duck/releases/latest",
      {
        headers: { Accept: "application/vnd.github+json" },
        next: { revalidate: 3600 },
      }
    );
    if (!res.ok) {
      return null;
    }
    const data: GitHubRelease = await res.json();
    const dmgAsset = data.assets?.find((a) => a.name.endsWith(".dmg"));
    return {
      downloadUrl: dmgAsset?.browser_download_url ?? RELEASES_URL,
      sizeMb: dmgAsset?.size
        ? `${(dmgAsset.size / 1024 / 1024).toFixed(1)} MB`
        : null,
      version: data.tag_name,
    };
  } catch {
    return null;
  }
}

export default async function HomePage() {
  const release = await getLatestRelease();
  // Empty when unknown, so the footer omits it rather than asserting a stale tag.
  const version = release?.version ?? "";
  const downloadUrl = release?.downloadUrl ?? RELEASES_URL;
  const sizeMb = release?.sizeMb ?? null;

  return (
    <main className="isolate flex min-h-dvh flex-col bg-canvas">
      {/* Root page only, and matched word for word by the BreadcrumbList in
          lib/config.ts. Outside the vertically centred block so it stays at the
          top of the page rather than drifting with the hero.

          The padding sits on the outer element and the measure on the inner
          one, exactly as the hero block below does it. With `px-6` on the same
          element as `max-w-[62ch]` the padding eats into the measure, so this
          row started 24px right of the app icon it is supposed to line up
          with. */}
      <div className="px-6 pt-8">
        <div className="mx-auto flex w-full max-w-[62ch] items-center justify-between gap-4">
          <ZoneBreadcrumb product="Rubber Duck" />
          {/*
            The repo link every visitor who scrolls past the download looks for,
            hoisted out of the footer. Icon only, so the accessible name comes
            from aria-label; the icon itself is decorative.

            Negative margin pulls the button's own padding back so the glyph,
            not the hit area, aligns with the measure. The empty span grows the
            target to 48px on touch, where 36px is under the minimum.
          */}
          <a
            aria-label="View on GitHub"
            className="relative -mr-2 inline-flex size-9 shrink-0 items-center justify-center rounded-lg text-ink-subtle transition-colors hover:bg-white/8 hover:text-ink focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2"
            href={siteConfig.links.github}
            rel="noopener noreferrer"
            target="_blank"
          >
            {/*
              Inlined for the same reason as the Apple mark below: one glyph,
              and the only icon package installed here draws GitHub as a thin
              outline that reads as a generic cat next to a solid brand mark.
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
            <span
              aria-hidden="true"
              className="-translate-1/2 absolute top-1/2 left-1/2 pointer-fine:hidden size-[max(100%,3rem)]"
            />
          </a>
        </div>
      </div>

      {/* One block, centred in the viewport, everything inside left-aligned.
          Margins live on these children rather than a gap, because the spacing
          between them is deliberately uneven. */}
      <div className="flex flex-1 flex-col justify-center px-6 pt-10 pb-16">
        <div className="mx-auto w-full max-w-[62ch]">
          <Image
            alt="Rubber Duck"
            className="rounded-[22%] shadow-2xl"
            height={80}
            priority
            src="/rubber-duck/app-icon.png"
            width={80}
          />

          <h1 className="mt-6 text-balance font-semibold text-4xl text-ink tracking-tight">
            Rubber Duck
          </h1>

          <p className="mt-2.5 text-ink-muted text-lg">
            Talk through your code with AI.
          </p>

          <p className="mt-5 text-pretty text-base text-ink-subtle">
            Ask questions out loud, hear answers back, and understand unfamiliar
            code faster. Point it at a directory and it can read files, edit
            them, and run commands there.
          </p>

          <div className="mt-7 flex items-center gap-3.5">
            <a
              className="inline-flex items-center gap-[7px] rounded-lg bg-white px-4 py-2.5 font-semibold text-black text-sm hover:opacity-80 focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-4 active:opacity-60"
              href={downloadUrl}
            >
              <svg
                aria-hidden="true"
                className="relative -top-px"
                fill="currentColor"
                height="14"
                viewBox="0 0 814 1000"
                width="12"
              >
                <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57.8-155.5-127.4c-58.3-81.8-105.3-209.2-105.3-330.3 0-194.3 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8.6 15.7 1.3 18.2 2.6.6 6.4 1.3 10.2 1.3 45.4 0 103.5-30.4 139.5-71.4z" />
              </svg>
              Download for macOS
            </a>
            {sizeMb ? <p className="text-ink-faint text-sm">{sizeMb}</p> : null}
          </div>

          <p className="mt-3 text-ink-faint text-sm">
            OpenAI API key required · Requires macOS 15.2
          </p>

          {/*
            The thing that separates it from a chat window is that it can open
            the files you are asking about, on your machine. Collapsed rather
            than cut, so the page stays one screen tall while the copy stays in
            the DOM.
          */}
          <FaqDisclosure />
        </div>
      </div>

      <SiteFooter version={version} />
    </main>
  );
}
