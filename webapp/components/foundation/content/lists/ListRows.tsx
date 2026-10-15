import { PlayerPortrait } from "@/components/foundation/content/prompts/PlayerPortrait";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import { teamLogoCode } from "@/lib/foundation/content/nfl/team-logos";
import { listTeamName, placeChange } from "@/lib/foundation/lists/lists";
import type { ListPlayer } from "@/lib/foundation/lists/types";

/** What an item in a list looks like: a team's logo and name, or a player's face and name. */
export function ListItemFace({
  item,
  itemKind,
  players,
}: {
  item: string;
  itemKind: "team" | "player";
  players: Record<string, ListPlayer>;
}) {
  if (itemKind === "team") {
    const logo = teamLogoCode(item);
    return (
      <span className="flex min-w-0 items-center gap-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-chip bg-panel-shade">
          {logo ? <TeamLogo code={logo} className="h-7 w-7" /> : <span className="type-label-xs text-panel-muted">{item}</span>}
        </span>
        <span className="min-w-0 leading-tight">
          <span className="block truncate text-[15px] font-semibold text-panel-fg">{listTeamName(item)}</span>
          <span className="block type-label-xs text-panel-muted">{item}</span>
        </span>
      </span>
    );
  }
  const player = players[item];
  return (
    <span className="flex min-w-0 items-center gap-3">
      <PlayerPortrait name={player?.name ?? "Player"} headshotUrl={player?.headshotUrl} className="h-9 w-9" />
      <span className="min-w-0 leading-tight">
        <span className="block truncate text-[15px] font-semibold text-panel-fg">{player?.name ?? "Unknown player"}</span>
        {player ? <span className="block type-label-xs text-panel-muted">{player.position} · {player.team}</span> : null}
      </span>
    </span>
  );
}

/** How far an item moved against an earlier list, as a short mark. Says nothing when there is no earlier list. */
export function PlaceChange({ change }: { change: number | null | undefined }) {
  if (change === undefined) return null;
  if (change === null) return <span className="type-label-xs text-panel-fg">New</span>;
  if (change === 0) return <span aria-label="Did not move" className="type-label-xs text-panel-muted">–</span>;
  return (
    <span className={`type-label-xs ${change > 0 ? "text-panel-fg" : "text-panel-muted"}`}>
      <span aria-hidden>{change > 0 ? "▲" : "▼"} {Math.abs(change)}</span>
      <span className="sr-only">{change > 0 ? `Up ${change}` : `Down ${-change}`}</span>
    </span>
  );
}

/**
 * A saved list, in order. With `previous`, each row also shows how far it
 * moved against that earlier version.
 */
export function ListRows({
  items,
  itemKind,
  players,
  previous,
}: {
  items: string[];
  itemKind: "team" | "player";
  players: Record<string, ListPlayer>;
  previous?: string[] | null;
}) {
  return (
    <ol className="divide-y divide-panel-line">
      {items.map((item, index) => (
        <li key={item} className="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-3 px-3 py-2">
          <span className="text-center font-slab text-2xl leading-none text-panel-fg tabular-nums">{index + 1}</span>
          <ListItemFace item={item} itemKind={itemKind} players={players} />
          {previous === undefined ? <span /> : <PlaceChange change={placeChange(previous, items, index)} />}
        </li>
      ))}
    </ol>
  );
}
