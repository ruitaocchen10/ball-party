import { forwardRef } from "react";

import { PromptTeamLogo } from "./PromptTeamLogo";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import type { Post } from "@/lib/foundation/content/prompts/types";

const CARD_WIDTH = 540;
const CARD_HEIGHT = 675;
const REEL_HEIGHT = 960;
const TICKET_CUT = "polygon(20px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 20px) 100%, 0 100%, 0 14px)";
export type ShareFormat = "post" | "reel";

/**
 * Fixed-size export board for a respondent's own Power Rankings ballot. The
 * card itself is always the 4:5 post size; the reel format only enlarges the
 * canvas around it, so the content sits centered rather than stretching.
 */
export const SharePowerRankingsCard = forwardRef<
  HTMLDivElement,
  { post: Post; responses: Record<string, string[]>; headline?: string; subheadline?: string; format?: ShareFormat }
>(function SharePowerRankingsCard({ post, responses, headline = post.templateName, subheadline = "My power rankings", format = "post" }, ref) {
  const slot = post.slots[0];
  const rankedOptions = (responses[slot?.id] ?? [])
    .map((id) => slot?.options.find((option) => option.id === id))
    .filter((option): option is NonNullable<typeof option> => Boolean(option));
  const count = rankedOptions.length;
  const columns = count > 10 ? 4 : count > 5 ? 2 : 1;
  const rows = Math.max(Math.ceil(count / columns), 1);
  const canvasHeight = format === "reel" ? REEL_HEIGHT : CARD_HEIGHT;

  return (
    <div ref={ref} style={{ width: CARD_WIDTH, height: canvasHeight, fontFamily: "var(--font-sans)" }} className="relative flex items-center justify-center overflow-hidden bg-[#111311] text-[#fffdf7]">
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          backgroundImage: [
            "linear-gradient(137deg, rgb(26 154 80 / 0.38) 0%, transparent 24%)",
            "linear-gradient(318deg, rgb(201 56 44 / 0.42) 0%, transparent 28%)",
            "linear-gradient(145deg, transparent 0%, transparent 48%, rgb(232 227 214 / 0.1) 48.2%, transparent 48.5%)",
            "radial-gradient(circle at center, rgb(232 227 214 / 0.07) 0.75px, transparent 1px)",
            "linear-gradient(160deg, #1a1e1a 0%, #101310 54%, #080a08 100%)",
          ].join(", "),
          backgroundSize: "auto, auto, auto, 9px 9px, auto",
        }}
      />
      <div className="relative z-10 shrink-0" style={{ width: CARD_WIDTH, height: CARD_HEIGHT }}>
        <header className="flex h-[138px] flex-col items-center justify-center px-8 text-center">
          <p className="max-w-full overflow-hidden font-mono text-xs font-semibold tracking-[0.18em] text-[#c9382c] text-ellipsis whitespace-nowrap uppercase">{subheadline}</p>
          <h1 className="max-w-full overflow-hidden font-slab text-[66px] leading-[0.9] text-ellipsis whitespace-nowrap uppercase">{headline}</h1>
        </header>

        <div className="px-6 pb-6" style={{ height: CARD_HEIGHT - 138 }}>
          <div className="grid h-full gap-2" style={{ gridAutoFlow: "column", gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`, gridTemplateRows: `repeat(${rows}, minmax(0, 1fr))` }}>
            {rankedOptions.map((option, index) => (
              <ShareRankCard key={option.id} option={option} rank={index + 1} previousRank={option.teamCode ? post.previousRankByTeam?.[option.teamCode] : undefined} compact={count > 10} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
});

function ShareRankCard({ option, rank, previousRank, compact }: { option: NonNullable<Post["slots"][number]["options"][number]>; rank: number; previousRank?: number; compact: boolean }) {
  const movement = previousRank === undefined ? null : previousRank - rank;
  const movementText = movement === null || movement === 0 ? "—" : movement > 0 ? `↑${movement}` : `↓${Math.abs(movement)}`;
  const movementColor = movement !== null && movement > 0 ? "text-[#23b863]" : movement !== null && movement < 0 ? "text-[#e04239]" : "text-[#74766f]";
  return (
    <div
      style={{
        clipPath: TICKET_CUT,
        background: `linear-gradient(135deg, ${option.teamCode ? teamPrimaryColor(option.teamCode) ?? "#30332e" : "#30332e"}, #151714 72%)`,
      }}
      className="relative grid min-w-0 grid-cols-[42px_minmax(0,1fr)_24px] overflow-hidden border border-white/25 shadow-[0_5px_12px_rgb(0_0_0/0.35)]"
    >
      <span className="relative z-10 flex items-center justify-center border-r border-white/20 bg-black/45 font-slab text-[34px] leading-none tabular-nums">{rank}</span>
      <span className="relative flex items-center justify-center overflow-hidden">
        {option.teamCode ? <PromptTeamLogo code={option.teamCode} className={compact ? "h-40 w-40 drop-shadow-[0_6px_8px_rgb(0_0_0/0.6)]" : "h-60 w-60 drop-shadow-[0_8px_12px_rgb(0_0_0/0.6)]"} /> : null}
        <span className="sr-only">{option.label}</span>
      </span>
      <span className={`relative z-10 flex items-center justify-center border-l border-black/20 bg-[#f7f5ee] font-mono text-xs font-black tabular-nums ${movementColor}`}>{movementText}</span>
    </div>
  );
}
