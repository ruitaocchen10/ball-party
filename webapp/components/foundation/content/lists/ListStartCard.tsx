import { PromptCover } from "@/components/foundation/content/prompts/PromptCover";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { resizedHeadshotUrl } from "@/lib/foundation/content/nfl/headshots";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import { COVER_PLAYER_IDS, listTitle } from "@/lib/foundation/lists/lists";
import type { ListKind, ListPlayer } from "@/lib/foundation/lists/types";

// A fixed spread of teams for the Power Rankings cover. It is art, the same for everyone, like a prompt's cover.
const COVER_TEAMS = ["BUF", "KC", "DET", "PHI", "BAL", "SF"].map((code) => ({ id: code, label: code, teamCode: code }));

/** Rank numerals tilted in alternating directions, the cover for a list of players. */
function RankNumerals() {
  const tilts = ["-rotate-[8deg]", "rotate-[6deg]", "-rotate-[5deg]", "rotate-[9deg]", "-rotate-[7deg]", "rotate-[5deg]"];
  return (
    <div aria-hidden className="absolute inset-0 flex items-center justify-around px-3">
      {tilts.map((tilt, index) => (
        <span key={index} className={`${tilt} font-slab text-6xl leading-none text-fg/80 drop-shadow-[0_6px_8px_rgb(0_0_0/0.7)] sm:text-7xl`}>
          {index + 1}
        </span>
      ))}
    </div>
  );
}

/** NFL.com headshots are all 3400 x 2450: head and shoulders on a transparent background. */
const HEADSHOT_ASPECT = "3400 / 2450";

/**
 * A lineup of the position's best: each player's headshot standing on a column
 * of their team's color, side by side across the cover. Each column crops the
 * photo to its middle, so the face stays centered at any width.
 */
function PlayerLineup({ players }: { players: ListPlayer[] }) {
  return (
    <div aria-hidden className="absolute inset-0 flex">
      {players.map((player) => (
        <div
          key={player.id}
          // A team's primary color is data, not a token, as on the prompt boards.
          style={{ background: `linear-gradient(to top, ${teamPrimaryColor(player.team) ?? "#30332e"}, transparent 85%)` }}
          className="relative min-w-0 flex-1 overflow-hidden border-r border-white/10 last:border-r-0"
        >
          {/* eslint-disable-next-line @next/next/no-img-element -- a decorative cutout whose size is set by its column; next/image would add nothing */}
          <img
            src={resizedHeadshotUrl(player.headshotUrl!, 400)}
            alt=""
            style={{ aspectRatio: HEADSHOT_ASPECT }}
            className="absolute bottom-0 left-1/2 h-[92%] max-w-none -translate-x-1/2 object-cover object-top drop-shadow-[0_6px_8px_rgb(0_0_0/0.5)]"
          />
        </div>
      ))}
    </div>
  );
}

/**
 * A list the player hasn't started, shaped like a prompt's feed card: the art
 * across the top, the title and what it is under it, and one button to begin.
 * Teams get the logo cover; players get a lineup of the position's best, or tilted rank numerals when their photos are not available.
 */
export function ListStartCard({ kind, players = {} }: { kind: ListKind; players?: Record<string, ListPlayer> }) {
  const lineup = (COVER_PLAYER_IDS[kind.id] ?? []).flatMap((id) => (players[id]?.headshotUrl ? [players[id]] : []));
  return (
    <Card>
      {kind.itemKind === "team" ? (
        <PromptCover
          testId={`list-cover-${kind.id}`}
          ariaLabel={`${kind.label} cover`}
          leftGlow="bg-[radial-gradient(ellipse_at_left,rgb(34_197_94_/_0.22),transparent_75%)]"
          rightGlow="bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_75%)]"
          art={null}
          logos={COVER_TEAMS}
        />
      ) : (
        <PromptCover
          testId={`list-cover-${kind.id}`}
          ariaLabel={`${kind.label} cover`}
          leftGlow="bg-[radial-gradient(ellipse_at_left,rgb(59_130_246_/_0.22),transparent_75%)]"
          rightGlow="bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_75%)]"
          art={lineup.length >= 3 ? <PlayerLineup players={lineup} /> : <RankNumerals />}
        />
      )}
      <div className="px-4 pt-3">
        <h2 className="font-slab text-2xl leading-[1.05] uppercase">{listTitle(kind, kind.sizes[0])}</h2>
        <p className="pt-0.5 text-[13px] text-fg-muted">
          {kind.itemKind === "team" ? "Rank the teams. Friends can see it and reply when you change it." : `Rank your top ${kind.sizes[0]}. Friends can see it and reply when you change it.`}
        </p>
      </div>
      <div className="px-4 pt-3 pb-4">
        <ButtonLink href={`/lists/${kind.id}`}>Start your list</ButtonLink>
      </div>
    </Card>
  );
}
