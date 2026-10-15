import type { ReactNode } from "react";
import { Flame, Shield, ThumbsDown, Trophy } from "lucide-react";

import { PROMPT_ART_HEIGHT } from "./PromptCover";

// Medal colors are art, like the other covers' blue and red, so they are
// written out rather than taken from tokens.
const MEDAL_TONES = {
  blue: { color: "rgb(59 130 246)", glow: "bg-[radial-gradient(ellipse_at_left,rgb(59_130_246_/_0.24),transparent_70%)]" },
  red: { color: "rgb(239 68 68)", glow: "bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_70%)]" },
} as const;

/** A medal: a ribbon over a shaded disc, with the award's icon on it. */
function Medal({ tone, size, className, children }: { tone: keyof typeof MEDAL_TONES; size: number; className: string; children: ReactNode }) {
  const { color } = MEDAL_TONES[tone];
  return (
    <div aria-hidden className={`absolute drop-shadow-[0_6px_8px_rgb(0_0_0/0.65)] ${className}`} style={{ width: size }}>
      <svg viewBox="0 0 40 20" className="block" style={{ width: size, height: size / 2 }} fill={color} opacity={0.85}>
        <path d="M6 0h10l8 20H14zM34 0H24l-8 20h10z" />
      </svg>
      <div
        className="grid place-items-center rounded-full text-white ring-[3px] ring-white/25 ring-inset"
        style={{ width: size, height: size, marginTop: -size * 0.12, background: `radial-gradient(circle at 35% 30%, ${color}, color-mix(in srgb, ${color} 55%, transparent))` }}
      >
        {children}
      </div>
    </div>
  );
}

/** A football on its side, laces showing. */
function Football({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden>
      <g transform="rotate(-40 12 12)">
        <ellipse cx="12" cy="12" rx="10" ry="6.5" fill="currentColor" />
        <path d="M12 8.5v7M9.5 10v4M14.5 10v4M7.5 12h9" stroke="rgb(0 0 0 / 0.5)" strokeWidth="1.6" strokeLinecap="round" />
      </g>
    </svg>
  );
}

/** A bold letter L, drawn as a shape so the cover stays wordless. */
function LetterL({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M7 3h5v13h6v5H7z" />
    </svg>
  );
}

/**
 * The Weekly Awards feed art: six medals, one per award, blue on the left and
 * red on the right at mixed sizes and tilts. Left, edge in: Offensive player
 * (football), Defensive player (shield), Biggest winner (trophy). Right: Best
 * game (flame), Biggest loser (thumbs down), LVP (an L). It carries no words,
 * because the card's title sits right under it.
 */
export function WeeklyAwardsBanner({ testId }: { testId: string }) {
  return (
    <section data-testid={testId} aria-label="Weekly Awards" className={`relative overflow-hidden bg-surface ${PROMPT_ART_HEIGHT}`}>
      <div aria-hidden className={`absolute inset-y-0 left-0 w-1/2 ${MEDAL_TONES.blue.glow}`} />
      <div aria-hidden className={`absolute inset-y-0 right-0 w-1/2 ${MEDAL_TONES.red.glow}`} />
      <Medal tone="blue" size={34} className="top-[39%] left-[5%] -rotate-[10deg]"><Football size={18} /></Medal>
      <Medal tone="blue" size={48} className="top-[25%] left-[17%] rotate-6"><Shield aria-hidden fill="currentColor" className="h-6 w-6" strokeWidth={1.5} /></Medal>
      <Medal tone="blue" size={64} className="top-[5%] left-[32%] -rotate-[4deg]"><Trophy aria-hidden fill="currentColor" className="h-8 w-8" strokeWidth={1.5} /></Medal>
      <Medal tone="red" size={64} className="top-[12%] right-[32%] rotate-[5deg]"><Flame aria-hidden fill="currentColor" className="h-8 w-8" strokeWidth={1.5} /></Medal>
      <Medal tone="red" size={48} className="top-[32%] right-[17%] -rotate-[7deg]"><ThumbsDown aria-hidden fill="currentColor" className="h-6 w-6" strokeWidth={1.5} /></Medal>
      <Medal tone="red" size={34} className="top-[45%] right-[5%] rotate-[9deg]"><LetterL size={18} /></Medal>
    </section>
  );
}
