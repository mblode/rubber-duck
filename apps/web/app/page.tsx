import Image from "next/image";

import { FaqDisclosure } from "@/components/faq-disclosure";
import { SiteFooter } from "@/components/site-footer";

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
      {/* One block, centred in the viewport, everything inside left-aligned.
          Margins live on these children rather than a gap, because the spacing
          between them is deliberately uneven. */}
      <div className="flex flex-1 flex-col justify-center px-6 py-16">
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
