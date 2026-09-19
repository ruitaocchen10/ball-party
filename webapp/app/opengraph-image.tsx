import { renderOgCard } from "@/lib/seo/og-card";

export const alt = "Ball Party — sports knowledge party games";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/** The default link preview for every page that doesn't draw its own. */
export default function Image() {
  return renderOgCard({ title: "Sports knowledge party games", eyebrow: "Play with your friends" });
}
