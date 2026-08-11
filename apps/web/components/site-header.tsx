import Image from "next/image";
import { Container } from "@/components/ui/section";
import { ZoneBreadcrumb } from "@/components/zone-breadcrumb";
import { siteConfig } from "@/lib/config";

export const SiteHeader = () => (
  <header className="border-white/8 border-b bg-canvas">
    <Container className="flex h-16 items-center justify-between gap-4">
      <div className="flex min-w-0 items-center gap-3">
        <Image
          alt=""
          className="size-8 shrink-0 rounded-[22%]"
          height={32}
          priority
          src="/rubber-duck/app-icon.png"
          width={32}
        />
        <ZoneBreadcrumb product="Rubber Duck" />
      </div>
      <a
        className="relative shrink-0 text-ink-subtle hover:text-ink focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-4"
        href={siteConfig.links.github}
        rel="noopener noreferrer"
        target="_blank"
      >
        <svg
          aria-hidden="true"
          className="size-5"
          fill="currentColor"
          viewBox="0 0 24 24"
        >
          <path d="M12 .7a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2.23c-3.22.7-3.9-1.37-3.9-1.37-.52-1.34-1.28-1.7-1.28-1.7-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.57-.3-5.27-1.29-5.27-5.69 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.47.11-3.06 0 0 .97-.31 3.16 1.18A10.93 10.93 0 0 1 12 6.11c.98 0 1.95.13 2.86.39 2.2-1.49 3.16-1.18 3.16-1.18.63 1.59.23 2.77.12 3.06.74.81 1.18 1.83 1.18 3.09 0 4.41-2.71 5.39-5.29 5.68.42.36.79 1.07.79 2.16v3.24c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .7Z" />
        </svg>
        <span className="sr-only">GitHub</span>
        <span
          aria-hidden="true"
          className="-translate-1/2 absolute top-1/2 left-1/2 pointer-fine:hidden size-[max(100%,3rem)]"
        />
      </a>
    </Container>
  </header>
);
