import Image from "next/image";

interface GitHubRelease {
  tag_name: string;
  assets: Array<{
    name: string;
    browser_download_url: string;
    size: number;
  }>;
}

async function getLatestRelease() {
  try {
    const res = await fetch(
      "https://api.github.com/repos/mblode/rubber-duck/releases/latest",
      {
        next: { revalidate: 3600 },
        headers: { Accept: "application/vnd.github+json" },
      },
    );
    if (!res.ok) return null;
    const data: GitHubRelease = await res.json();
    const dmgAsset = data.assets?.find((a) => a.name.endsWith(".dmg"));
    return {
      version: data.tag_name,
      downloadUrl: dmgAsset?.browser_download_url ?? null,
      sizeMb: dmgAsset?.size
        ? `${(dmgAsset.size / 1024 / 1024).toFixed(1)} MB`
        : null,
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
    <main className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center text-center gap-5 px-6">
        <div className="w-[84px] h-[84px] rounded-[19px] overflow-hidden shadow-2xl">
          <Image
            src="/app-icon.png"
            alt="RubberDuck"
            width={84}
            height={84}
            priority
          />
        </div>

        <h1 className="text-[28px] font-semibold tracking-tight text-white">
          RubberDuck
        </h1>

        <p className="text-[15px] text-white/55 -mt-2">
          Your voice coding agent, in the menu bar.
        </p>

        <p className="text-[13px] text-white/35 leading-relaxed max-w-[260px]">
          Voice commands, file tools, AI coding sessions.
          <br />
          One hotkey instead of switching between apps.
        </p>

        <div className="flex items-center gap-3 mt-1">
          <a
            href={downloadUrl}
            className="inline-flex items-center gap-[7px] bg-white text-black text-[13px] font-medium px-4 py-[9px] rounded-[8px] hover:bg-white/90 transition-colors"
          >
            <svg
              width="12"
              height="14"
              viewBox="0 0 814 1000"
              fill="currentColor"
              aria-hidden="true"
              style={{ position: "relative", top: "-1px" }}
            >
              <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57.8-155.5-127.4c-58.3-81.8-105.3-209.2-105.3-330.3 0-194.3 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8.6 15.7 1.3 18.2 2.6.6 6.4 1.3 10.2 1.3 45.4 0 103.5-30.4 139.5-71.4z" />
            </svg>
            Download for macOS
          </a>
          {sizeMb && (
            <span className="text-[12px] text-white/30">{sizeMb}</span>
          )}
        </div>

        <span className="flex items-center gap-[7px] text-[12px] text-white/30">
          <span className="bg-white/10 text-white/45 px-[6px] py-[2px] rounded-[4px] text-[10px] font-medium uppercase tracking-wide">
            Beta
          </span>
          {version} · Requires macOS Tahoe
        </span>
      </div>
    </main>
  );
}
