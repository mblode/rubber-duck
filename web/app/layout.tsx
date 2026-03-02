import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Agentation } from "agentation";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Rubber Duck — Voice coding agent for macOS",
  description:
    "Voice commands, file tools, AI coding sessions. One hotkey instead of switching between apps.",
  metadataBase: new URL("https://rubber-duck.blode.co"),
  appleWebApp: {
    title: "Rubber Duck",
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
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
        {process.env.NODE_ENV === "development" && <Agentation />}
      </body>
    </html>
  );
}
