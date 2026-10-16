import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { Barlow, Bebas_Neue, JetBrains_Mono } from "next/font/google";
import "./globals.css";

import { MotionProvider } from "@/components/foundation/ui-kit/MotionProvider";
import { NoFlashSidebarScript } from "@/components/foundation/ui-kit/NoFlashSidebarScript";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "@/lib/seo/site";

// Barlow reads; Bebas Neue is the display voice and is only ever used large;
// JetBrains Mono carries every stat line, budget, and clock.
const barlow = Barlow({
  variable: "--font-barlow",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

// Bebas Neue ships a single weight, so next/font requires it explicitly.
const bebasNeue = Bebas_Neue({
  variable: "--font-bebas-neue",
  subsets: ["latin"],
  weight: "400",
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: `${SITE_NAME} · Sports knowledge party games`,
    template: `%s · ${SITE_NAME}`,
  },
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  // A child that sets its own `openGraph` replaces this object rather than
  // merging into it, so pages that do (prompt detail) repeat siteName and type.
  openGraph: {
    type: "website",
    siteName: SITE_NAME,
    locale: "en_US",
  },
  twitter: { card: "summary_large_image" },
};

// Matches --surface in globals.css, so the mobile browser chrome and the
// installed app's splash sit on the same near-black as the page.
export const viewport: Viewport = { themeColor: "#111311" };

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${barlow.variable} ${bebasNeue.variable} ${jetbrainsMono.variable} h-full antialiased`}
      // The no-flash script below sets data-sidebar-collapsed on this element
      // before React hydrates, which never matches the server-rendered markup
      // (SSR has no localStorage to read). That mismatch is intentional, not a
      // bug — this is the standard escape hatch for exactly this pattern.
      suppressHydrationWarning
    >
      <head>
        <NoFlashSidebarScript />
      </head>
      <body className="flex min-h-full flex-col">
        <MotionProvider>{children}</MotionProvider>
        <Analytics />
      </body>
    </html>
  );
}
