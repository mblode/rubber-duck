import type { Metadata } from "next";
import localFont from "next/font/local";
import { Agentation } from "agentation";
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
  title: "Rubber Duck | Talk through your code with AI",
  description:
    "Ask questions out loud, hear answers back, and understand unfamiliar code faster.",
  metadataBase: new URL("https://rubber-duck.blode.co"),
  appleWebApp: {
    title: "Rubber Duck",
  },
  verification: {
    google: "mFwyBIbXTaKK4uF_NA0MzVWFyY40hPgBjFObg3rje04",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${glide.variable} antialiased`}
      >
        {children}
        {process.env.NODE_ENV === "development" && <Agentation />}
      </body>
    </html>
  );
}
