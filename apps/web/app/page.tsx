import Image from "next/image";

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
      downloadUrl: dmgAsset?.browser_download_url ?? null,
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
  const version = release?.version ?? "v0.0.5";
  const downloadUrl = release?.downloadUrl ?? "#";
  const sizeMb = release?.sizeMb ?? null;

  return (
    <main className="flex min-h-dvh flex-col overflow-hidden bg-[#1c1c1e]">
      <div className="flex flex-1 flex-col items-start justify-center px-[clamp(24px,8vw,180px)] pt-16 md:mx-auto md:pt-0">
        <div className="h-[84px] w-[84px] overflow-hidden rounded-[19px] shadow-2xl">
          <Image
            alt="Rubber Duck"
            height={84}
            priority
            src="/rubber-duck/app-icon.png"
            width={84}
          />
        </div>

        <h1 className="mt-6 font-bold text-[#f5f5f7] text-[clamp(28px,5vw,38px)] leading-none tracking-[-0.035em]">
          Rubber Duck
        </h1>

        <p className="mt-2.5 font-medium text-[#c5c5ca] text-[17px]">
          Talk through your code with AI.
        </p>

        <p className="mt-5 font-light text-[#98989d] text-[14px] leading-[1.7]">
          Ask questions out loud, hear answers back, and understand unfamiliar
          code faster.
        </p>

        <div className="mt-7 inline-flex items-center gap-[14px]">
          <a
            className="inline-flex items-center gap-[7px] rounded-[8px] bg-white px-4 py-[9px] font-medium text-[13px] text-black transition-colors hover:bg-white/90"
            href={downloadUrl}
          >
            <svg
              aria-hidden="true"
              fill="currentColor"
              height="14"
              style={{ position: "relative", top: "-1px" }}
              viewBox="0 0 814 1000"
              width="12"
            >
              <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57.8-155.5-127.4c-58.3-81.8-105.3-209.2-105.3-330.3 0-194.3 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8.6 15.7 1.3 18.2 2.6.6 6.4 1.3 10.2 1.3 45.4 0 103.5-30.4 139.5-71.4z" />
            </svg>
            Download for macOS
          </a>
          {sizeMb ? (
            <span className="text-[#636366] text-[13px]">{sizeMb}</span>
          ) : null}
        </div>

        <span className="mt-3 text-[#636366] text-[12px]">
          OpenAI API key required
        </span>

        {/*
          45 words before this, none of which explained the thing that makes it
          different from talking to a chat window: it can open the files you are
          asking about, and it does that on your machine.
        */}
        <section className="mt-16 max-w-[62ch] space-y-4 font-light text-[#98989d] text-[14px] leading-[1.7]">
          <h2 className="font-medium text-[#c5c5ca] text-[15px]">
            How it works
          </h2>

          <p>
            Rubber Duck is the debugging technique with the duck swapped for
            something that answers back. It lives in the macOS menu bar. Press
            Option and D, ask the question out loud, and it replies out loud.
            Half the value of explaining a problem to a duck is the explaining,
            and this one can ask you what you meant.
          </p>

          <p>
            What separates it from talking at a chat window is that it can see
            the code you are describing. Point the duck command at a directory
            and the menu bar app switches to that workspace straight away. From
            there it has real tools: read a file, grep the tree, find files by
            name, run a command, make an edit. Those run locally through a small
            daemon over a Unix socket, so the model asks for a file and your own
            machine is what opens it.
          </p>

          <p>
            Audio goes to the OpenAI Realtime API as 24 kHz mono, on your own
            API key, kept in the macOS Keychain. You pay for the minutes you
            talk and there is no subscription. If the daemon happens not to be
            running the app still works, you just get the conversation without
            the tools, and the command line half installs itself the first time
            you launch it.
          </p>
        </section>
      </div>

      <SiteFooter version={version} />
    </main>
  );
}
