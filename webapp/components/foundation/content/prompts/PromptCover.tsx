import type { ReactNode } from "react";

import { OptionIcon } from "./SlotFaces";
import type { Option } from "@/lib/foundation/content/prompts/types";

export const COVER_LOGO_COUNT = 6;

/** The height every prompt card's art shares, so a feed of different kinds keeps one rhythm. */
export const PROMPT_ART_HEIGHT = "h-28 sm:h-32";

/** Logos tilt in alternating directions so a row of six reads as a spread, not a table. */
const LOGO_TILTS = ["-rotate-[10deg]", "rotate-[8deg]", "-rotate-[6deg]", "rotate-[10deg]", "-rotate-[8deg]", "rotate-[6deg]"] as const;

/**
 * The art across the top of a prompt's feed card: a short, full-bleed banner
 * with a colored glow on each side, the kind's motif shapes, and up to six
 * tilted team logos in a row. It carries no words, because the card's title and
 * subtitle sit right under it. Each prompt kind supplies only its own colors
 * and art.
 */
export function PromptCover({
  testId,
  ariaLabel,
  leftGlow,
  rightGlow,
  art,
  logos = [],
}: {
  testId: string;
  ariaLabel: string;
  /** Tailwind gradient classes for the left and right side glows. */
  leftGlow: string;
  rightGlow: string;
  /** Motif shapes, absolutely positioned inside the banner. */
  art: ReactNode;
  /** Optional tilted team logos; covers built from their motif alone omit them. */
  logos?: Option[];
}) {
  const shown = logos.slice(0, COVER_LOGO_COUNT);
  return (
    <section data-testid={testId} aria-label={ariaLabel} className={`relative overflow-hidden bg-surface ${PROMPT_ART_HEIGHT}`}>
      <div aria-hidden className={`absolute inset-y-0 left-0 w-1/2 ${leftGlow}`} />
      <div aria-hidden className={`absolute inset-y-0 right-0 w-1/2 ${rightGlow}`} />
      {art}

      {shown.length > 0 ? (
        <div className="absolute inset-0 flex items-center justify-around px-3 pt-4">
          {shown.map((option, index) => (
            <div key={option.id} className={`${LOGO_TILTS[index]} drop-shadow-[0_6px_8px_rgb(0_0_0/0.8)]`}>
              <OptionIcon option={option} className="h-12 w-12 sm:h-16 sm:w-16" />
            </div>
          ))}
        </div>
      ) : null}
    </section>
  );
}
