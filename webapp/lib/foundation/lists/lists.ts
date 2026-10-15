import { franchiseName } from "@/lib/foundation/content/nfl/franchises";
import { teamLogoCode } from "@/lib/foundation/content/nfl/team-logos";

/** Moves one item to another place, shifting the ones between. */
export function moveItem<T>(items: readonly T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return [...items];
  const next = [...items];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
}

/**
 * How far an item moved against an earlier list: positive when it climbed,
 * negative when it fell, 0 when it stayed, and null when it was not in the
 * earlier list.
 */
export function placeChange(previous: readonly string[] | null, items: readonly string[], index: number): number | null {
  if (!previous) return null;
  const was = previous.indexOf(items[index]);
  return was < 0 ? null : was - index;
}

/** How many places hold a different item than the earlier list did. */
export function movedCount(previous: readonly string[] | null, items: readonly string[]): number {
  if (!previous) return items.length;
  return items.filter((item, index) => previous[index] !== item).length;
}

export type ListMove = { item: string; place: number; change: number | null };

/**
 * The moves worth naming on a card: new entries first, then the biggest
 * climbs and falls, up to `limit`. Without an earlier list there is nothing to
 * compare, so it is empty.
 */
export function biggestMoves(previous: readonly string[] | null, items: readonly string[], limit = 4): ListMove[] {
  if (!previous) return [];
  return items
    .map((item, index) => ({ item, place: index + 1, change: placeChange(previous, items, index) }))
    .filter((move) => move.change !== 0)
    .sort((a, b) => Math.abs(b.change ?? Infinity) - Math.abs(a.change ?? Infinity) || a.place - b.place)
    .slice(0, limit);
}

/** The team's display name, or the code itself for one the app does not know. */
export function listTeamName(code: string): string {
  const logo = teamLogoCode(code);
  return logo ? franchiseName(logo) : code;
}

/** The sizes a kind offers as tab labels: "Top 10", "All 32". */
export function sizeLabel(size: number, itemKind: "team" | "player"): string {
  return itemKind === "team" && size === 32 ? "All 32" : `Top ${size}`;
}

/** Where a list is read and edited. */
export function listPath(kind: string, username?: string | null): string {
  return username ? `/u/${encodeURIComponent(username)}/lists/${kind}` : `/lists/${kind}`;
}

/**
 * The 32 teams a team list can hold (nflverse codes). The database checks the
 * same set when a list is saved; this is only the pool the editor offers.
 */
export const NFL_TEAM_CODES = [
  "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET", "GB", "HOU", "IND", "JAX", "KC",
  "LAC", "LAR", "LV", "MIA", "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS",
] as const;

/** The teams not in a list, in alphabetical order, for the editor's bench. */
export function benchTeams(items: readonly string[]): string[] {
  return NFL_TEAM_CODES.filter((code) => !items.includes(code));
}

/** A list after its size changes: cut from the bottom, or filled from the bench. */
export function resizeTeams(items: readonly string[], size: number): string[] {
  return items.length >= size ? items.slice(0, size) : [...items, ...benchTeams(items)].slice(0, size);
}

/**
 * Adds list updates to the home feed's items, newest first. Both are paged
 * with `?before=`, and the feed's own window is bounded below by `floor` (the
 * oldest game moment on a full page), so updates outside the window wait for
 * their page.
 */
export function mergeByTime<A extends { at: string }, B extends { at: string }>(
  items: A[],
  updates: B[],
  { before, floor }: { before: string | null; floor: string | null },
): (A | B)[] {
  const inWindow = updates.filter(
    (update) => (before === null || Date.parse(update.at) < Date.parse(before)) && (floor === null || Date.parse(update.at) >= Date.parse(floor)),
  );
  return [...items, ...inWindow].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
}

/** A list's heading on a card: "My power rankings - V3", "My top 10 QBs - V3". Without a version (a list not started yet) it is just the name. */
export function listTitle(kind: { id: string; itemKind: "team" | "player" }, size: number, versionNo?: number): string {
  const name = kind.itemKind === "team" ? "My power rankings" : `My top ${size} ${kind.id.toUpperCase()}s`;
  return versionNo === undefined ? name : `${name} - V${versionNo}`;
}

/**
 * Whose faces stand on a position list's cover before the player has started
 * it: five of the best at the position, left to right, by nflverse player id.
 * Picked by hand. Changing the lineup is an edit here, and an id the player
 * directory doesn't know is skipped.
 */
export const COVER_PLAYER_IDS: Record<string, string[]> = {
  qb: ["00-0036389", "00-0034796", "00-0033873", "00-0034857", "00-0036442"], // Hurts, Jackson, Mahomes, Allen, Burrow
  rb: ["00-0038542", "00-0032764", "00-0034844", "00-0033280", "00-0039139"], // Robinson, Henry, Barkley, McCaffrey, Gibbs
  wr: ["00-0036963", "00-0036358", "00-0036322", "00-0036900", "00-0039075"], // St. Brown, Lamb, Jefferson, Chase, Nacua
};
