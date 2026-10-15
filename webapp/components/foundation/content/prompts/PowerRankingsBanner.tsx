import { PROMPT_ART_HEIGHT } from "./PromptCover";
import { OptionIcon } from "./SlotFaces";
import type { Option } from "@/lib/foundation/content/prompts/types";

// Each cover logo's place on the banner: how far in from its own edge and down
// from the top (percent, so the spread follows the card's width and height) and
// its size. They are art, not UI chrome, so the sizes are written out rather
// than taken from tokens. Listed outside in: risers climb toward the middle and
// grow as they go (so #1 is the biggest, nearest the middle), fallers fall away
// from it and shrink (#4 nearest the middle, #6 at the edge).
const RISERS = [
  { x: "left-[3%]", y: "top-[57%]", size: "h-9 w-9 sm:h-10 sm:w-10" },
  { x: "left-[13%]", y: "top-[37%]", size: "h-[54px] w-[54px] sm:h-16 sm:w-16" },
  { x: "left-[27%]", y: "top-[2%]", size: "h-[92px] w-[92px] sm:h-[104px] sm:w-[104px]" },
] as const;
const FALLERS = [
  { x: "right-[27%]", y: "top-[18%]", size: "h-[92px] w-[92px] sm:h-[104px] sm:w-[104px]" },
  { x: "right-[13%]", y: "top-[41%]", size: "h-[54px] w-[54px] sm:h-16 sm:w-16" },
  { x: "right-[3%]", y: "top-[61%]", size: "h-9 w-9 sm:h-10 sm:w-10" },
] as const;

/** A block arrow pointing up; the falling side flips it. */
function BlockArrow({ className }: { className: string }) {
  return (
    <svg aria-hidden viewBox="0 0 24 36" className={`absolute ${className}`} fill="currentColor">
      <path d="M12 0 24 15H16V36H8V15H0Z" />
    </svg>
  );
}

/**
 * The Power Rankings feed art: the six teams the admin chose, in placement
 * order, the first three climbing on the green side and the last three falling
 * on the red, each side with a big vertical block arrow behind its logos. It is
 * the same for every viewer.
 */
export function PowerRankingsBanner({ options, testId }: { options: Option[]; testId: string }) {
  const risers = options.slice(0, RISERS.length);
  const fallers = options.slice(RISERS.length, RISERS.length + FALLERS.length);
  return (
    <section data-testid={testId} aria-label="Power Rankings board" className={`relative overflow-hidden bg-surface ${PROMPT_ART_HEIGHT}`}>
      <div aria-hidden className="absolute inset-y-0 left-0 w-1/2 bg-[radial-gradient(ellipse_at_left,rgb(34_197_94_/_0.26),transparent_75%)]" />
      <div aria-hidden className="absolute inset-y-0 right-0 w-1/2 bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.26),transparent_75%)]" />
      <BlockArrow className="top-[12%] left-[7%] h-[78%] text-green-500/30" />
      <BlockArrow className="top-[10%] right-[7%] h-[78%] rotate-180 text-red-500/30" />
      {risers.map((option, index) => (
        <OptionIcon key={option.id} option={option} className={`absolute drop-shadow-[0_6px_8px_rgb(0_0_0/0.7)] ${RISERS[RISERS.length - 1 - index].x} ${RISERS[RISERS.length - 1 - index].y} ${RISERS[RISERS.length - 1 - index].size}`} />
      ))}
      {fallers.map((option, index) => (
        <OptionIcon key={option.id} option={option} className={`absolute drop-shadow-[0_6px_8px_rgb(0_0_0/0.7)] ${FALLERS[index].x} ${FALLERS[index].y} ${FALLERS[index].size}`} />
      ))}
    </section>
  );
}
