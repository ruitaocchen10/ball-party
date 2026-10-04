import type { ReactNode } from "react";

import { OptionIcon } from "./SlotFaces";
import { PROMPT_TICKET_CUT_CORNERS } from "./PromptTicket";
import type { Option } from "@/lib/foundation/content/prompts/types";

export const COVER_LOGO_COUNT = 6;

const SHAPE_POLYGONS = {
  chevronUp: "polygon(50% 0,100% 58%,82% 58%,50% 25%,18% 58%,0 58%)",
  chevronDown: "polygon(0 42%,18% 42%,50% 75%,82% 42%,100% 42%,50% 100%)",
  bolt: "polygon(58% 0,8% 56%,42% 56%,32% 100%,92% 38%,56% 38%)",
  star: "polygon(50% 0,61% 35%,98% 35%,68% 57%,79% 91%,50% 70%,21% 91%,32% 57%,2% 35%,39% 35%)",
} as const;

export type CoverShapeKind = keyof typeof SHAPE_POLYGONS;

/** Bold filled shapes carry each cover's motif without reading as text glyphs. */
export function CoverShape({ shape, className }: { shape: CoverShapeKind; className: string }) {
  return <span aria-hidden className={`absolute block ${className}`} style={{ clipPath: SHAPE_POLYGONS[shape], backgroundColor: "currentColor" }} />;
}

/** Logo placement order: 1–2 are the large top corners, 3–4 the large bottom corners, 5–6 the smaller middle pair. */
const LOGO_SLOTS = [
  { position: "absolute -top-1 -left-4 rotate-[-18deg] opacity-90", size: "h-24 w-24 sm:h-28 sm:w-28" },
  { position: "absolute -top-1 -right-4 rotate-[18deg] opacity-90", size: "h-24 w-24 sm:h-28 sm:w-28" },
  { position: "absolute bottom-2 -left-4 rotate-[14deg] opacity-75", size: "h-24 w-24 sm:h-28 sm:w-28" },
  { position: "absolute right-0 bottom-2 rotate-[-14deg] opacity-75", size: "h-24 w-24 sm:h-28 sm:w-28" },
  { position: "absolute top-1/2 left-[15%] z-[1] -translate-y-1/2 rotate-[12deg] opacity-75", size: "h-16 w-16 sm:h-20 sm:w-20" },
  { position: "absolute top-1/2 right-[15%] z-[1] -translate-y-1/2 rotate-[-12deg] opacity-75", size: "h-16 w-16 sm:h-20 sm:w-20" },
] as const;

/**
 * The shared prompt cover: a dark ticket with a colored glow and motif shapes
 * on each side, up to six tilted team logos, and a centered two-line title
 * with a single subheadline. Each prompt kind supplies only its own words,
 * colors and art.
 */
export function PromptCover({
  testId,
  ariaLabel,
  title,
  subtitle,
  leftGlow,
  rightGlow,
  art,
  logos = [],
}: {
  testId: string;
  ariaLabel: string;
  /** Top line in white, bottom line in red. */
  title: [string, string];
  subtitle: string;
  /** Tailwind gradient classes for the left and right side glows. */
  leftGlow: string;
  rightGlow: string;
  /** Motif shapes, absolutely positioned inside the cover. */
  art: ReactNode;
  /** Optional tilted team logos; covers built from their motif alone omit them. */
  logos?: Option[];
}) {
  return (
    <section data-testid={testId} aria-label={ariaLabel} style={PROMPT_TICKET_CUT_CORNERS} className="relative mx-4 mt-4 min-h-52 overflow-hidden bg-[#11130f] text-[#fff8e4] shadow-[0_10px_20px_rgb(0_0_0/0.35)]">
      <div aria-hidden className={`absolute inset-y-0 left-0 w-1/2 ${leftGlow}`} />
      <div aria-hidden className={`absolute inset-y-0 right-0 w-1/2 ${rightGlow}`} />
      {art}

      {logos.slice(0, COVER_LOGO_COUNT).map((option, index) => (
        <div key={option.id} className={`${LOGO_SLOTS[index].position} drop-shadow-[0_8px_10px_rgb(0_0_0/0.8)]`}>
          <OptionIcon option={option} className={LOGO_SLOTS[index].size} />
        </div>
      ))}

      <div className="relative z-10 flex min-h-52 flex-col items-center justify-center px-16 text-center [text-shadow:0_3px_0_rgb(0_0_0),0_6px_14px_rgb(0_0_0/0.9)]">
        <h3 className="font-slab text-4xl leading-[0.78] tracking-[-0.04em] uppercase sm:text-5xl">
          <span className="block text-white">{title[0]}</span>
          <span className="block text-[#ef4444]">{title[1]}</span>
        </h3>
        <p className="mt-3 font-mono text-[9px] tracking-[0.12em] text-[#fff8e4]/85 uppercase">{subtitle}</p>
      </div>
    </section>
  );
}
