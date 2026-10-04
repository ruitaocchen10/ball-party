import type { ReactNode } from "react";

import { PlayerPortrait } from "./PlayerPortrait";
import { PromptTeamLogo } from "./PromptTeamLogo";
import { describeTarget, type BoldPredictionBoardData, type BoldTarget } from "@/lib/foundation/content/prompts/boldPredictions";

/** The small ticket silhouette, a step down from PROMPT_TICKET_CUT_CORNERS for a card that sits inside another. */
const QUOTE_CUT_CORNERS = { clipPath: "polygon(14px 0, 100% 0, 100% calc(100% - 8px), calc(100% - 14px) 100%, 0 100%, 0 8px)" };

/**
 * One prediction as a poster line: the call in the heading face, with its tag
 * as oversized faded art behind the right edge — both clubs for a matchup,
 * the logo for a team, the headshot for a player. The tag's name stays for
 * screen readers and for the filter chips above.
 */
export function BoldQuote({ body, target, data, actions }: {
  body: string;
  target: BoldTarget;
  data: Pick<BoldPredictionBoardData, "weekGames" | "players">;
  /** Controls under the quote, for a draft that can still change. */
  actions?: ReactNode;
}) {
  const { label, teamCodes, player } = describeTarget(target, data);
  return (
    <div style={QUOTE_CUT_CORNERS} className="relative overflow-hidden border border-line bg-surface">
      {/* The art owns this column; the text's right padding below matches it plus a gutter, so they never overlap. */}
      <div aria-hidden className="pointer-events-none absolute inset-y-0 right-0 flex w-32 items-center justify-center overflow-hidden opacity-[0.2] sm:w-44">
        {target.type === "player" ? (
          <PlayerPortrait name={label} headshotUrl={player?.headshotUrl} className="h-28 w-28 text-4xl sm:h-36 sm:w-36" />
        ) : (
          <span className="flex -space-x-6">
            {teamCodes.map((code) => (
              <PromptTeamLogo key={code} code={code} className={teamCodes.length > 1 ? "h-16 w-16 sm:h-20 sm:w-20" : "h-28 w-28 sm:h-36 sm:w-36"} />
            ))}
          </span>
        )}
      </div>
      <div className="relative flex min-h-24 min-w-0 flex-col justify-center py-4 pr-36 pl-5 sm:pr-48">
        <p className="font-slab text-2xl leading-[1.05] tracking-[0.01em] break-words whitespace-pre-wrap text-fg uppercase sm:text-3xl">&ldquo;{body}&rdquo;</p>
        {actions ? <div className="mt-3">{actions}</div> : null}
      </div>
      <span className="sr-only">{target.type === "matchup" ? "Matchup" : target.type === "team" ? "Team" : "Player"}: {label}</span>
    </div>
  );
}
