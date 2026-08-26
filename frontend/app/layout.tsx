import type { Metadata } from "next";
import { Barlow, Bebas_Neue, JetBrains_Mono } from "next/font/google";
import "./globals.css";

import { MotionProvider } from "@/components/motion/MotionProvider";

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
  title: "Ball Party",
  description: "Sports knowledge party games with your friends.",
};

// Runs before first paint so a reload lands at the sidebar width the user
// last chose instead of flashing expanded-then-collapsing. Mirrors the
// classic no-flash dark-mode script — same reasoning, one attribute.
const NO_FLASH_SIDEBAR_SCRIPT = `
  try {
    if (localStorage.getItem("sidebar-collapsed") === "true") {
      document.documentElement.setAttribute("data-sidebar-collapsed", "");
    }
  } catch (e) {}
`;

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
        <script dangerouslySetInnerHTML={{ __html: NO_FLASH_SIDEBAR_SCRIPT }} />
      </head>
      <body className="flex min-h-full flex-col">
        <MotionProvider>{children}</MotionProvider>
      </body>
    </html>
  );
}
