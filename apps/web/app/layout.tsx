import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { Agentation } from "agentation";
import { JsonLd } from "@/components/json-ld";
import { siteConfig } from "@/lib/config";
import "./globals.css";

const glide = localFont({
  src: [
    { path: "../public/glide-variable.woff2", style: "normal" },
    { path: "../public/glide-variable-italic.woff2", style: "italic" },
  ],
  variable: "--font-glide",
  weight: "400 900",
  display: "swap",
});

export const metadata: Metadata = {
  title: siteConfig.title,
  description: siteConfig.description,
  metadataBase: new URL(siteConfig.url),
  alternates: {
    canonical: siteConfig.url,
  },
  appleWebApp: {
    title: siteConfig.name,
  },
  openGraph: {
    type: "website",
    siteName: siteConfig.name,
    title: siteConfig.title,
    description: siteConfig.description,
    url: siteConfig.url,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: siteConfig.title,
    description: siteConfig.description,
  },
  robots: {
    index: true,
    follow: true,
  },
  verification: {
    google: "mFwyBIbXTaKK4uF_NA0MzVWFyY40hPgBjFObg3rje04",
  },
};

export const viewport: Viewport = {
  themeColor: "#1c1c1e",
  colorScheme: "dark",
};

const personId = `${siteConfig.url}/#person`;
const websiteId = `${siteConfig.url}/#website`;
const appId = `${siteConfig.url}/#software`;

const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Person",
      "@id": personId,
      name: siteConfig.author,
      url: siteConfig.links.author,
      image: `${siteConfig.url}/matthew-blode-profile.jpg`,
      sameAs: [siteConfig.links.author, "https://github.com/mblode"],
    },
    {
      "@type": "WebSite",
      "@id": websiteId,
      name: siteConfig.name,
      url: siteConfig.url,
      publisher: { "@id": personId },
    },
    {
      "@type": "SoftwareApplication",
      "@id": appId,
      name: siteConfig.name,
      description: siteConfig.description,
      url: siteConfig.url,
      applicationCategory: "DeveloperApplication",
      operatingSystem: "macOS",
      image: `${siteConfig.url}/web-app-manifest-512x512.png`,
      author: { "@id": personId },
      isPartOf: { "@id": websiteId },
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
      },
    },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className={`${glide.variable} antialiased`}>
        {children}
        <JsonLd data={structuredData} />
        {process.env.NODE_ENV === "development" && <Agentation />}
      </body>
    </html>
  );
}
