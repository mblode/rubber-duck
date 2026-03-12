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
    <main className="relative flex items-center min-h-dvh bg-[#1c1c1e] overflow-hidden">
      <div className="flex flex-col items-start text-left pl-[clamp(40px,12vw,180px)] pr-10">
        <div className="w-[84px] h-[84px] rounded-[19px] overflow-hidden shadow-2xl">
          <Image
            src="/app-icon.png"
            alt="Rubber Duck"
            width={84}
            height={84}
            priority
          />
        </div>

        <h1 className="text-[38px] font-bold tracking-[-0.035em] leading-none text-[#f5f5f7] mt-6">
          Rubber Duck
        </h1>

        <p className="text-[17px] font-medium text-[#c5c5ca] mt-2.5">
          Talk through your code with AI.
        </p>

        <p className="text-[14px] font-light leading-[1.7] text-[#98989d] mt-5">
          Ask questions out loud, hear answers back, and understand unfamiliar
          code faster.
        </p>

        <div className="inline-flex items-center gap-[14px] mt-7">
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
            <span className="text-[13px] text-[#636366]">{sizeMb}</span>
          )}
        </div>

        <span className="text-[12px] text-[#636366] mt-3">
          {version} · macOS 15.2+ · OpenAI API key required
        </span>
      </div>

      <p className="absolute bottom-7 left-[clamp(40px,12vw,180px)] text-[12px] text-[#48484a]">
        © {new Date().getFullYear()} Matthew Blode ·{" "}
        <a
          href="https://github.com/mblode/rubber-duck"
          className="hover:text-[#636366] transition-colors"
        >
          GitHub
        </a>
      </p>
    </main>
  );
}
