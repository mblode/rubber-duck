import { Agentation } from "agentation";
import type { Metadata, Viewport } from "next";
import { Geist_Mono, Inter } from "next/font/google";
import { JsonLd } from "@/components/json-ld";
import {
  appId,
  breadcrumbId,
  breadcrumbSchema,
  orgId,
  personId,
  siteConfig,
  webPageId,
  websiteId,
} from "@/lib/config";
import { PAGE_UPDATED, TOOLS } from "@/lib/content";
import { getLatestRelease } from "@/lib/release";
import "./globals.css";

const inter = Inter({
  display: "swap",
  subsets: ["latin"],
  variable: "--font-inter",
});

const geistMono = Geist_Mono({
  display: "swap",
  subsets: ["latin"],
  variable: "--font-geist-mono",
});

export const metadata: Metadata = {
  alternates: {
    canonical: siteConfig.url,
  },
  appleWebApp: {
    title: siteConfig.name,
  },
  authors: [{ name: siteConfig.author, url: siteConfig.links.author }],
  creator: siteConfig.author,
  description: siteConfig.description,
  metadataBase: new URL(siteConfig.url),
  openGraph: {
    description: siteConfig.description,
    locale: "en_US",
    // Every zone is a path on blode.co, so the site is the person. The product
    // name already has the og:title slot; repeating it here would spend the one
    // field in the card that could say who made the thing.
    siteName: siteConfig.author,
    title: siteConfig.title,
    type: "website",
    url: siteConfig.url,
  },
  robots: {
    follow: true,
    index: true,
  },
  title: {
    default: siteConfig.title,
    template: `%s | ${siteConfig.name}`,
  },
  twitter: {
    card: "summary_large_image",
    creator: "@mattblode",
    description: siteConfig.description,
    title: siteConfig.title,
  },
  verification: {
    google: "mFwyBIbXTaKK4uF_NA0MzVWFyY40hPgBjFObg3rje04",
  },
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#0d0d0f",
};

/*
 * The Person and WebSite nodes are blode.co's and are referenced by `@id`, not
 * redefined here. See the note on the ids in `lib/config.ts`.
 */
/**
 * `featureList` is the seven tools the voice agent is actually given, taken
 * from `apps/macos/Tools/ToolDefinitions.swift` and executed by
 * `cli/src/daemon/voice-tools.ts`. It is not a keyword list: a feature named
 * here that a reviewer cannot find in that dispatcher is a markup error, not a
 * marketing decision. The rendered table on the page is built from the same
 * seven, so the graph and the page cannot disagree about what this thing does.
 */
const FEATURE_LIST = TOOLS.rows.map((tool) => `${tool.name}: ${tool.does}`);

const structuredData = (version: string) => ({
  "@context": "https://schema.org",
  "@graph": [
    {
      "@id": webPageId,
      "@type": "WebPage",
      about: { "@id": appId },
      breadcrumb: { "@id": breadcrumbId },
      // Hand-maintained in lib/content.ts and shared with the visible <time> in
      // the closing section and with app/sitemap.ts. Deliberately not a build
      // clock: "changed on every deploy" is not a freshness signal.
      dateModified: PAGE_UPDATED,
      description: siteConfig.description,
      inLanguage: "en-US",
      isPartOf: { "@id": websiteId },
      name: siteConfig.name,
      url: siteConfig.url,
    },
    {
      "@id": appId,
      "@type": "SoftwareApplication",
      // Stays `DeveloperApplication`, unlike commandment, which was moved off
      // it. That app types into Slack and Mail as readily as into an editor;
      // this one takes a repo path and runs `grep`, so the category is right.
      applicationCategory: "DeveloperApplication",
      author: { "@id": personId },
      description: siteConfig.description,
      downloadUrl: `${siteConfig.links.github}/releases/latest`,
      featureList: FEATURE_LIST,
      // The generated OG card, not the 512px manifest icon. Google asks for at
      // least 1200px on the wide side, and the icon fell well under it. Same
      // source commandment, convene and moon already point at.
      image: `${siteConfig.url}/opengraph-image`,
      isAccessibleForFree: true,
      isPartOf: { "@id": websiteId },
      license: `${siteConfig.links.github}/blob/main/LICENSE.md`,
      name: siteConfig.name,
      offers: {
        "@type": "Offer",
        availability: "https://schema.org/InStock",
        // Numeric 0 matches Google's SoftwareApplication example. String "0"
        // is schema.org-legal but Semrush Site Audit flags it as invalid markup.
        price: 0,
        priceCurrency: "USD",
        url: siteConfig.url,
      },
      operatingSystem: "macOS 15.2",
      publisher: { "@id": orgId },
      // Omitted rather than guessed when the GitHub API is unreachable. An
      // absent property is honest; a stale one is a claim.
      ...(version ? { softwareVersion: version } : {}),
      url: siteConfig.url,
    },
    breadcrumbSchema(),
  ],
});

/**
 * Async so the graph can publish the same `softwareVersion` the page renders.
 * `getLatestRelease` is one `fetch` shared with `app/page.tsx` — identical
 * arguments are deduplicated within a render pass and both read the same 3600s
 * cache entry, so this is not a second request.
 */
export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const { version } = await getLatestRelease();

  return (
    <html
      className={`scheme-only-dark dark ${inter.variable} ${geistMono.variable}`}
      lang="en"
    >
      <head>
        <link
          href={process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://r.blode.co"}
          rel="preconnect"
        />
      </head>
      <body className="antialiased">
        {children}
        <JsonLd data={structuredData(version)} />
        {process.env.NODE_ENV === "development" && <Agentation />}
      </body>
    </html>
  );
}
