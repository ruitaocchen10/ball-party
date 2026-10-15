import { PROMPT_ART_HEIGHT } from "./PromptCover";

// Bubble colors are art, like the other covers' blue and red, so they are
// written out rather than taken from tokens.
const BUBBLE_TONES = {
  blue: { color: "rgb(59 130 246)", glow: "bg-[radial-gradient(ellipse_at_left,rgb(59_130_246_/_0.24),transparent_70%)]" },
  red: { color: "rgb(239 68 68)", glow: "bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_70%)]" },
} as const;

/** A speech bubble with an exclamation mark in it, its tail at the lower left. */
function Bubble({ tone, size, className }: { tone: keyof typeof BUBBLE_TONES; size: number; className: string }) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 40 36"
      style={{ width: size, height: size * 0.9 }}
      className={`absolute drop-shadow-[0_6px_8px_rgb(0_0_0/0.65)] ${className}`}
    >
      <path d="M6 2h28a5 5 0 0 1 5 5v16a5 5 0 0 1-5 5H20l-9 7v-7H6a5 5 0 0 1-5-5V7a5 5 0 0 1 5-5z" fill={BUBBLE_TONES[tone].color} fillOpacity={0.9} />
      <rect x="18" y="7" width="4.4" height="12" rx="2.2" fill="white" />
      <circle cx="20.2" cy="23" r="2.4" fill="white" />
    </svg>
  );
}

/**
 * The Bold Predictions feed art: six "!" speech bubbles, blue calling from the
 * left and red from the right, at mixed sizes and tilts, the biggest nearest the
 * middle.
 * It carries no words, because the card's title sits right under it.
 */
export function BoldPredictionsBanner({ testId }: { testId: string }) {
  return (
    <section data-testid={testId} aria-label="Bold Predictions" className={`relative overflow-hidden bg-surface ${PROMPT_ART_HEIGHT}`}>
      <div aria-hidden className={`absolute inset-y-0 left-0 w-1/2 ${BUBBLE_TONES.blue.glow}`} />
      <div aria-hidden className={`absolute inset-y-0 right-0 w-1/2 ${BUBBLE_TONES.red.glow}`} />
      <Bubble tone="blue" size={34} className="top-[44%] left-[4%] -rotate-[8deg]" />
      <Bubble tone="blue" size={50} className="top-[22%] left-[15%] rotate-[5deg]" />
      <Bubble tone="blue" size={68} className="top-[3%] left-[29%] -rotate-[5deg]" />
      <Bubble tone="red" size={68} className="top-[10%] right-[29%] rotate-6" />
      <Bubble tone="red" size={50} className="top-[34%] right-[15%] -rotate-6" />
      <Bubble tone="red" size={34} className="top-[48%] right-[4%] rotate-[9deg]" />
    </section>
  );
}
