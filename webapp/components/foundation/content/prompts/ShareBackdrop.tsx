import type { CSSProperties } from "react";

/**
 * The stage behind every downloadable share graphic, and the header type set
 * on it. Only plain CSS gradients: html-to-image rasterizes through an SVG
 * foreignObject, where blend modes, backdrop filters and SVG noise are
 * unreliable.
 *
 * Three layers, top to bottom: a vignette that pulls the edges down so the
 * team-colored tiles read as lit; one soft floodlight behind the headline; and
 * flat mown bands. Flat bands rather than a smooth gradient because
 * Instagram's JPEG pass turns a near-black gradient into visible steps, while
 * flat color survives it. The charcoal is deliberately neutral — the app's own
 * surface color has a green cast that looked muddy behind the tiles.
 */
export const SHARE_THEME = {
  /** Fill behind the layers, also the fallback if a layer fails to paint. */
  base: "#171716",
  /** Headline color — the tiles keep their own light-on-dark text. */
  ink: "#fffdf7",
  kicker: "#e0473a",
  // Header type, in the card's 540px working size. Bebas Neue ships one
  // weight, so the headline's extra weight is a text stroke.
  headlinePx: 76,
  headlineStroke: 1.25,
  kickerPx: 14,
  kickerWeight: 800,
} as const;

/** Height of one mown band, in the card's 540px working size. */
const BAND = 56;

const layers = (glowY: number) => [
  "radial-gradient(135% 88% at 50% 46%, transparent 48%, rgb(0 0 0 / 0.6) 100%)",
  `radial-gradient(88% 40% at 50% ${glowY}px, rgb(255 250 240 / 0.12), transparent 74%)`,
  `repeating-linear-gradient(180deg, #1c1c1b 0 ${BAND}px, #151514 ${BAND}px ${BAND * 2}px)`,
];

export const shareKickerStyle: CSSProperties = {
  color: SHARE_THEME.kicker,
  fontSize: SHARE_THEME.kickerPx,
  fontWeight: SHARE_THEME.kickerWeight,
};

export const shareHeadlineStyle: CSSProperties = {
  color: SHARE_THEME.ink,
  fontSize: SHARE_THEME.headlinePx,
  WebkitTextStroke: `${SHARE_THEME.headlineStroke}px ${SHARE_THEME.ink}`,
};

/**
 * Absolutely fills its card; render it as the card's first child. `glowY` is
 * the y position, in px from the canvas top, to center the floodlight on —
 * the headline, which sits lower on a reel than on a post.
 */
export function ShareBackdrop({ glowY }: { glowY: number }) {
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0"
      style={{ backgroundColor: SHARE_THEME.base, backgroundImage: layers(glowY).join(", ") }}
    />
  );
}
