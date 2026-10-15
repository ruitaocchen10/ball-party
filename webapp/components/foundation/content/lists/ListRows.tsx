import type { CSSProperties, ReactNode } from "react";

import { PlayerPortrait } from "@/components/foundation/content/prompts/PlayerPortrait";
import { PromptTeamLogo } from "@/components/foundation/content/prompts/PromptTeamLogo";
import { PROMPT_TICKET_CUT_CORNERS } from "@/components/foundation/content/prompts/PromptTicket";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import { listTeamName, placeChange } from "@/lib/foundation/lists/lists";
import type { ListPlayer } from "@/lib/foundation/lists/types";

/**
 * How far an item moved against an earlier list, as a short mark. Says nothing
 * when there is no earlier list. It sits on the tile's cream cell, so up and
 * down use the grade colors the prompt boards use.
 */
export function PlaceChange({ change }: { change: number | null | undefined }) {
  if (change === undefined) return null;
  // Not in the earlier list reads as "–", like the prompt boards; screen readers still hear "New".
  if (change === null) return <span className="font-mono text-xs font-black text-fg-muted"><span aria-hidden>–</span><span className="sr-only">New</span></span>;
  if (change === 0) return <span className="font-mono text-xs font-black text-fg-muted"><span aria-hidden>–</span><span className="sr-only">Did not move</span></span>;
  return (
    <span className={`font-mono text-xs font-black tabular-nums ${change > 0 ? "text-grade-elite" : "text-grade-rough"}`}>
      <span aria-hidden>{change > 0 ? "+" : "−"}{Math.abs(change)}</span>
      <span className="sr-only">{change > 0 ? `Up ${change}` : `Down ${-change}`}</span>
    </span>
  );
}

/** "Buffalo Bills" → "Bills". A team's logo already says the city. */
function teamNickname(code: string): string {
  const name = listTeamName(code);
  return name === code ? code : (name.split(" ").pop() ?? name);
}

/** "Amon-Ra St. Brown" → "St. Brown". */
function surname(name: string): string {
  const [, ...rest] = name.trim().split(/\s+/);
  return rest.length ? rest.join(" ") : name;
}

/**
 * One item in a list, drawn like the Power Rankings board's ticket: rank, the
 * team's logo or the player's face, a short name, and (against an earlier
 * list) how far it moved. Renders a button when `onClick` is given, so the
 * editor can pick it up; `aria-label` then names it for a screen reader.
 *
 * `rank` is null for a team on the bench.
 */
export function ListTile({
  item,
  itemKind,
  players,
  rank,
  change,
  picked = false,
  onClick,
  disabled = false,
  ariaLabel,
  trailing,
}: {
  item: string;
  itemKind: "team" | "player";
  players: Record<string, ListPlayer>;
  rank: number | null;
  change?: number | null;
  picked?: boolean;
  onClick?: () => void;
  disabled?: boolean;
  ariaLabel?: string;
  /** Replaces the movement cell, for the bench's "Bring in" and a player's remove button. */
  trailing?: ReactNode;
}) {
  const player = itemKind === "player" ? players[item] : undefined;
  const team = itemKind === "team" ? item : player?.team;
  // A team's primary color is data, not a design token, so it is allowed here as it is on the prompt boards.
  const style: CSSProperties = {
    ...PROMPT_TICKET_CUT_CORNERS,
    ...(picked ? {} : { background: `linear-gradient(135deg, ${(team && teamPrimaryColor(team)) ?? "#252722"}, #171914 72%)` }),
  };
  const hasTrailing = trailing !== undefined || change !== undefined;
  const body = (
    <>
      <span className="z-10 flex items-center justify-center border-r border-white/20 bg-black/45 font-slab text-2xl leading-none tabular-nums">
        {rank ?? "+"}
      </span>
      <span className="flex min-w-0 items-center gap-2 px-2">
        {itemKind === "team" ? (
          <PromptTeamLogo code={item} className="h-9 w-9 drop-shadow-[0_3px_4px_rgb(0_0_0/0.6)]" />
        ) : (
          <PlayerPortrait name={player?.name ?? "Player"} headshotUrl={player?.headshotUrl} className="h-9 w-9" />
        )}
        <span className="min-w-0 leading-tight">
          <span className="block truncate font-slab text-lg uppercase">{itemKind === "team" ? teamNickname(item) : surname(player?.name ?? "Unknown")}</span>
          {player ? <span className="block truncate font-mono text-[10px] text-white/70">{player.position} · {player.team}</span> : null}
        </span>
      </span>
      {hasTrailing ? (
        <span className="relative z-10 flex w-9 items-center justify-center border-l border-black/15 bg-fg">
          {trailing ?? <PlaceChange change={change} />}
        </span>
      ) : null}
    </>
  );
  const className = `relative grid h-14 min-w-0 w-full overflow-hidden rounded-card border text-left text-white shadow-[0_4px_10px_rgb(0_0_0/0.28)] ${
    hasTrailing ? "grid-cols-[2.1rem_minmax(0,1fr)_auto]" : "grid-cols-[2.1rem_minmax(0,1fr)]"
  } ${picked ? "border-white bg-hidden" : "border-white/25"}`;

  if (!onClick) return <div style={style} className={className}>{body}</div>;
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={picked}
      aria-label={ariaLabel}
      style={style}
      className={`${className} transition-transform focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg enabled:hover:-translate-y-0.5 disabled:opacity-60`}
    >
      {body}
    </button>
  );
}

/**
 * The shape a list takes on the page, by how many items it is meant to hold:
 * a single column up to 5, two columns of 5 for a top 10, and for all 32 two
 * columns of 16 on a phone or four of 8 wider. It fills down each column
 * first, like the Power Rankings board.
 */
export function listGridClass(size: number): string {
  if (size > 10) return "grid grid-flow-col grid-cols-2 grid-rows-16 gap-1.5 sm:grid-cols-4 sm:grid-rows-8";
  if (size > 5) return "grid grid-flow-col grid-cols-2 grid-rows-5 gap-1.5";
  return "flex flex-col gap-1.5";
}

/** A saved list, in order, as tiles in columns. With `previous`, each tile shows how far it moved against that earlier version. */
export function ListRows({
  items,
  itemKind,
  players,
  previous,
  size = items.length,
}: {
  items: string[];
  itemKind: "team" | "player";
  players: Record<string, ListPlayer>;
  previous?: string[] | null;
  /** The size the list is laid out for, when it shows only part of itself. */
  size?: number;
}) {
  return (
    <ol className={`px-4 pb-4 ${listGridClass(size)}`}>
      {items.map((item, index) => (
        <li key={item} className="min-w-0">
          <ListTile
            item={item}
            itemKind={itemKind}
            players={players}
            rank={index + 1}
            change={previous === undefined ? undefined : placeChange(previous, items, index)}
          />
        </li>
      ))}
    </ol>
  );
}
