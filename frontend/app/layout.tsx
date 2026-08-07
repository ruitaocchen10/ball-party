import type { Metadata } from "next";
import { Alfa_Slab_One, Karla, Roboto_Mono } from "next/font/google";
import "./globals.css";

// Karla reads; Alfa Slab is the display voice and is only ever used large;
// Roboto Mono carries every stat line, budget, and clock.
const karla = Karla({
  variable: "--font-karla",
  subsets: ["latin"],
});

// Alfa Slab One ships a single weight, so next/font requires it explicitly.
const alfaSlabOne = Alfa_Slab_One({
  variable: "--font-alfa-slab",
  subsets: ["latin"],
  weight: "400",
});

const robotoMono = Roboto_Mono({
  variable: "--font-roboto-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Ball Party",
  description: "Sports knowledge party games with your friends.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${karla.variable} ${alfaSlabOne.variable} ${robotoMono.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
