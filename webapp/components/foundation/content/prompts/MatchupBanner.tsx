import { MoonStar } from "lucide-react";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import type { MatchupGameContext, Option, Slot } from "@/lib/foundation/content/prompts/types";
import { formatGameTime } from "./MatchupPicker";
import { PROMPT_ART_HEIGHT } from "./PromptCover";
import { PromptTeamLogo } from "./PromptTeamLogo";

/**
 * The two teams of a matchup slot, away then home. A Game Picks slot (winner
 * plus margin) lists four choices, "away by <7, away by 7+, home by <7, home by
 * 7+", so its teams are the first and third.
 */
export function matchupTeams(slot: Slot): [Option, Option] | null {
  const margin = slot.options.some((option) => option.margin);
  const [away, home] = margin ? [slot.options[0], slot.options[2]] : [slot.options[0], slot.options[1]];
  if (!away || !home) return null;
  const bare = (option: Option): Option => ({ ...option, label: option.label.replace(/ by .*$/, "") });
  return [bare(away), bare(home)];
}

/**
 * A single game's art, like a broadcast graphic: each club's color runs in from
 * its edge with its logo drawn oversized and bleeding off the side, and the two
 * names sit big in the middle over the kickoff and venue. A primetime game says
 * so in the top-left corner, opposite the card's timer chip.
 */
export function MatchupBanner({ slot, context, testId }: { slot: Slot; context?: MatchupGameContext; testId?: string }) {
  const teams = matchupTeams(slot);
  if (!teams) return null;
  const [away, home] = teams;
  // A team's own colors, so they can't be tokens. Without a known color the side stays the card's surface.
  const awayColor = (away.teamCode && teamPrimaryColor(away.teamCode)) || "transparent";
  const homeColor = (home.teamCode && teamPrimaryColor(home.teamCode)) || "transparent";
  return (
    <section
      data-testid={testId}
      aria-label={`${away.label} at ${home.label}`}
      className={`relative overflow-hidden bg-surface ${PROMPT_ART_HEIGHT}`}
      style={{ backgroundImage: `linear-gradient(90deg, ${awayColor}, transparent 42%, transparent 58%, ${homeColor})` }}
    >
      {away.teamCode ? <PromptTeamLogo code={away.teamCode} className="absolute top-1/2 -left-7 h-32 w-32 -translate-y-1/2 sm:-left-5 sm:h-36 sm:w-36" /> : null}
      {home.teamCode ? <PromptTeamLogo code={home.teamCode} className="absolute top-1/2 -right-7 h-32 w-32 -translate-y-1/2 sm:-right-5 sm:h-36 sm:w-36" /> : null}
      {context?.primetime ? (
        <Badge tone="scrim" size="xs" className="absolute top-2 left-2 z-10" icon={<MoonStar aria-hidden className="h-3 w-3" strokeWidth={2.2} />}>Primetime</Badge>
      ) : null}
      <div className="relative z-[1] flex h-full flex-col items-center justify-center gap-1 px-24 pt-5 text-center sm:px-32">
        <p className="flex max-w-full items-baseline gap-1.5 font-slab text-xl leading-none uppercase sm:text-2xl">
          <span className="truncate">{away.label}</span>
          <span aria-hidden className="shrink-0 text-sm text-fg-muted">@</span>
          <span className="truncate">{home.label}</span>
        </p>
        <p className="flex max-w-full items-center justify-center gap-1.5 type-label-xs text-fg/70">
          <span className="shrink-0">{formatGameTime(context?.kickoff)}</span>
          <span aria-hidden className="text-fg/30">·</span>
          <span className="truncate text-fg/50">{context?.stadium || "Venue TBD"}</span>
        </p>
      </div>
    </section>
  );
}

/** A slate's cover draws the first four games' clubs, away then home. The count is what says how big the week is. */
const SLATE_GAMES_SHOWN = 4;

/**
 * A weekly slate's art: the number of games as the headline, with the clubs of
 * the first four games fanned out beside it. Which games those are doesn't
 * matter, so it is just the first four in the prompt's order. A still, not a
 * pager: the detail screen is where a player goes through the games.
 */
export function SlateBanner({ slots, testId, label }: { slots: Slot[]; testId?: string; label: string }) {
  const games = slots.map(matchupTeams).filter((teams): teams is [Option, Option] => teams !== null);
  const clubs = games.slice(0, SLATE_GAMES_SHOWN).flat();
  return (
    <section data-testid={testId} aria-label={label} className={`relative flex items-center gap-4 overflow-hidden bg-surface px-4 pt-6 ${PROMPT_ART_HEIGHT}`}>
      <div aria-hidden className="absolute inset-y-0 left-0 w-1/2 bg-[radial-gradient(ellipse_at_left,rgb(59_130_246_/_0.2),transparent_70%)]" />
      <div aria-hidden className="absolute inset-y-0 right-0 w-1/2 bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.18),transparent_70%)]" />
      <div className="relative flex shrink-0 flex-col">
        <span className="font-slab text-6xl leading-[0.9]">{games.length}</span>
        <span className="pt-1 type-label-xs text-fg-muted">{games.length === 1 ? "Game" : "Games"} this week</span>
      </div>
      {/* Each logo takes an equal share of the room beside the count, up to a cap, so eight fit on a narrow phone. */}
      <div aria-hidden className="relative flex min-w-0 flex-1 items-center justify-end">
        {clubs.map((club, index) =>
          club.teamCode ? (
            <span key={`${club.id}-${index}`} className="-ml-1.5 aspect-square min-w-0 flex-1 basis-0 first:ml-0 max-w-12">
              <PromptTeamLogo code={club.teamCode} className="h-full w-full drop-shadow-[-3px_0_4px_rgb(0_0_0/0.5)]" />
            </span>
          ) : null,
        )}
      </div>
    </section>
  );
}
