import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { ImageResponse } from "next/og";

import { SITE_NAME, SITE_URL, truncate } from "@/lib/seo/site";

// The route files that call this export the same numbers as `size`, which Next
// needs to read as literals to write the og:image:width/height tags.
const SIZE = { width: 1200, height: 630 };

// The palette from globals.css, spelled out because ImageResponse renders
// standalone — no stylesheet, no CSS variables.
const SURFACE = "#111311";
const CREAM = "#f4efe4";
const FG = "#e8e3d6";
const MUTED = "#8f8b7f";
const LINE = "rgba(232, 227, 214, 0.22)";

type OgCardProps = {
  /** The big line. Long text is shortened and set smaller so it always fits. */
  title: string;
  /** Quiet line under the title — what kind of prompt this is. */
  eyebrow?: string;
  /** Short status chip in the corner, e.g. "Open". Omitted when there's nothing useful to say. */
  badge?: { label: string; filled?: boolean };
  /** For cards drawn per request, which Next won't cache on its own. Static cards leave this off. */
  cacheControl?: string;
};

/** Bebas Neue is condensed, so a few words can go very large; long prompts step down to stay within three lines. */
function titleSize(text: string): number {
  if (text.length <= 28) return 156;
  if (text.length <= 60) return 120;
  return 92;
}

/**
 * The link-preview card: near-black surface, the brand tile, and the prompt
 * set large in Bebas Neue — the same display voice the app uses for headlines.
 * Only public prompt text goes on it; no player names, picks or take content.
 */
export async function renderOgCard({ title, eyebrow, badge, cacheControl }: OgCardProps): Promise<ImageResponse> {
  const [font, mark] = await Promise.all([
    readFile(join(process.cwd(), "assets/fonts/BebasNeue-Regular.ttf")),
    readFile(join(process.cwd(), "public/brand/ball-party-mark-dark.svg")),
  ]);
  const markSrc = `data:image/svg+xml;base64,${mark.toString("base64")}`;
  const text = truncate(title, 110);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: SURFACE,
          color: FG,
          padding: 64,
          fontFamily: "Bebas Neue",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
            {/* eslint-disable-next-line @next/next/no-img-element -- ImageResponse is not the DOM; next/image doesn't apply */}
            <img src={markSrc} width={72} height={72} alt="" />
            <div style={{ fontSize: 52, letterSpacing: 2, color: CREAM }}>{SITE_NAME.toUpperCase()}</div>
          </div>
          {badge ? (
            <div
              style={{
                display: "flex",
                fontSize: 38,
                letterSpacing: 2,
                padding: "6px 22px",
                border: `2px solid ${badge.filled ? CREAM : LINE}`,
                background: badge.filled ? CREAM : "transparent",
                color: badge.filled ? SURFACE : CREAM,
              }}
            >
              {badge.label.toUpperCase()}
            </div>
          ) : null}
        </div>

        <div style={{ display: "flex", fontSize: titleSize(text), lineHeight: 0.95, color: CREAM, textTransform: "uppercase" }}>
          {text}
        </div>

        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", fontSize: 40, letterSpacing: 2 }}>
          <div style={{ display: "flex", color: MUTED }}>{eyebrow ? eyebrow.toUpperCase() : ""}</div>
          <div style={{ display: "flex", color: FG }}>{new URL(SITE_URL).host.toUpperCase()}</div>
        </div>
      </div>
    ),
    {
      ...SIZE,
      fonts: [{ name: "Bebas Neue", data: font, style: "normal", weight: 400 }],
      headers: cacheControl ? { "Cache-Control": cacheControl } : undefined,
    },
  );
}
