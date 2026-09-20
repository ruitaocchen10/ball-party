import { forwardRef } from "react";

import { CandidateTile, type TileMetrics } from "./CandidateTile";
import { SHARE_THEME, ShareBackdrop, shareHeadlineStyle, shareKickerStyle } from "./ShareBackdrop";
import type { ShareFormat } from "./shareFormat";
import { COVER_OPTION_LIMIT } from "@/lib/foundation/content/prompts/logic";
import type { Option } from "@/lib/foundation/content/prompts/types";

const CARD_WIDTH = 540; // doubled on export (see useShareImage's pixelRatio) for a 1080px-wide PNG.
const CARD_HEIGHT = 675; // 4:5 at the 540px working size; exported at 1080 × 1350.
const REEL_HEIGHT = 960; // 9:16; exported at 1080 × 1920.
const HEADER_HEIGHT = 192;
const SIDE_PADDING = 24;
const BOTTOM_PADDING = 24;
const TILE_GAP = 10;

const HEADLINE_SIZES = [70, 64, 58, 52, 46, 42, 38, 34, 30];
const HEADLINE_WIDTH = CARD_WIDTH - 64; // the header's 32px side padding
/** Room for the headline: the header less the kicker and its gap, and ~16px above and below. */
const HEADLINE_MAX_HEIGHT = HEADER_HEIGHT - 22 - 32;
/** Width of a Bebas Neue capital, per px of font size. Measured at ~0.345; a little over so a wrap is never underestimated. */
const CAP_WIDTH = 0.36;

function wrappedLines(headline: string, size: number): number {
  const charWidth = size * CAP_WIDTH;
  let lines = 1;
  let width = 0;
  for (const word of headline.trim().split(/\s+/)) {
    const wordWidth = word.length * charWidth;
    if (width === 0) width = wordWidth;
    else if (width + charWidth + wordWidth <= HEADLINE_WIDTH) width += charWidth + wordWidth;
    else {
      lines += 1;
      width = wordWidth;
    }
  }
  return lines;
}

/**
 * The largest headline size whose wrapped lines fit the header. Sized by
 * wrapping rather than length: a short question of long words takes more lines
 * than a longer one of short words.
 */
export function headlineFontSize(headline: string): number {
  return HEADLINE_SIZES.find((size) => wrappedLines(headline, size) * size * 0.98 <= HEADLINE_MAX_HEIGHT) ?? HEADLINE_SIZES[HEADLINE_SIZES.length - 1];
}

type ShareLayout = { columns: number; rows: number; metrics: TileMetrics };

/** Tile shape by how many candidates the art shows. */
const LAYOUTS: Record<number, ShareLayout> = {
  1: { columns: 1, rows: 1, metrics: { portraitHeight: "440px", headshotRequestWidth: 1220, logoClass: "h-[300px] w-[300px]", lastNameSize: 44, firstNameClass: "text-[18px]", plateClass: "px-5 pt-16 pb-5" } },
  2: { columns: 2, rows: 1, metrics: { portraitHeight: "400px", headshotRequestWidth: 1100, logoClass: "h-[224px] w-[224px]", lastNameSize: 34, firstNameClass: "text-[15px]", plateClass: "px-3 pt-14 pb-4" } },
  3: { columns: 3, rows: 1, metrics: { portraitHeight: "330px", headshotRequestWidth: 920, logoClass: "h-[150px] w-[150px]", lastNameSize: 26, firstNameClass: "text-[12px]", plateClass: "px-2.5 pt-12 pb-3.5" } },
  4: { columns: 2, rows: 2, metrics: { portraitHeight: "215px", headshotRequestWidth: 600, logoClass: "h-[120px] w-[120px]", lastNameSize: 24, firstNameClass: "text-[11px]", plateClass: "px-3 pt-9 pb-2.5" } },
};

/**
 * The downloadable graphic for a "pick one out of these" prompt: the question
 * and the candidates the art shows (the caller passes `coverOptions`), with
 * nothing chosen and no results — this is the post that asks, not the one that
 * shares an answer. Fixed pixel values, like the other share cards, so the
 * export doesn't depend on the admin's window.
 *
 * The card is always the 4:5 post size; the reel format only enlarges the
 * canvas around it, so the content sits centered rather than stretching.
 */
export const SharePromptCard = forwardRef<
  HTMLDivElement,
  { options: Option[]; headline: string; subheadline?: string; format?: ShareFormat }
>(function SharePromptCard({ options, headline, subheadline = "Pick one", format = "post" }, ref) {
  const shown = options.slice(0, COVER_OPTION_LIMIT);
  const layout = LAYOUTS[Math.max(shown.length, 1)];
  const canvasHeight = format === "reel" ? REEL_HEIGHT : CARD_HEIGHT;
  const bodyHeight = CARD_HEIGHT - HEADER_HEIGHT - BOTTOM_PADDING;
  const headlineSize = headlineFontSize(headline);

  return (
    <div ref={ref} style={{ width: CARD_WIDTH, height: canvasHeight, fontFamily: "var(--font-sans)", backgroundColor: SHARE_THEME.base }} className="relative flex items-center justify-center overflow-hidden text-[#fffdf7]">
      <ShareBackdrop glowY={(canvasHeight - CARD_HEIGHT) / 2 + HEADER_HEIGHT / 2} />
      <div className="relative z-10 shrink-0" style={{ width: CARD_WIDTH, height: CARD_HEIGHT }}>
        <header className="flex flex-col items-center justify-center gap-2 px-8 text-center" style={{ height: HEADER_HEIGHT }}>
          <p style={shareKickerStyle} className="max-w-full overflow-hidden font-mono tracking-[0.18em] text-ellipsis whitespace-nowrap uppercase">{subheadline}</p>
          <h1
            className="max-w-full overflow-hidden font-slab leading-[0.98] text-balance uppercase"
            style={{ ...shareHeadlineStyle, fontSize: headlineSize, maxHeight: headlineSize * 0.98 * 3 }}
          >
            {headline}
          </h1>
        </header>

        <div style={{ height: bodyHeight, padding: `0 ${SIDE_PADDING}px` }}>
          <div
            className="grid h-full"
            style={{ gap: TILE_GAP, gridTemplateColumns: `repeat(${layout.columns}, minmax(0, 1fr))`, gridTemplateRows: `repeat(${layout.rows}, minmax(0, 1fr))` }}
          >
            {shown.map((option) => (
              <CandidateTile key={option.id} option={option} metrics={layout.metrics} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
});
