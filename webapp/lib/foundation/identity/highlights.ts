import type { ProfileHighlights } from "@/components/foundation/identity/ProfileHighlights";
import {
  profileStatRanges,
  summarizeMultiplayerProfileRange,
  type CompletedMatchWithMode,
} from "@/lib/foundation/identity/summary";

/** Builds the profile highlights card from match history and the knower windows. Shared by /profile and /u/[username]. */
export function profileHighlights(
  matches: CompletedMatchWithMode[],
  knowerRows: { window_key: string; total_points: number; percentile: number | null; pick_points: number; like_points: number }[],
): ProfileHighlights {
  const knowerByRange = new Map(knowerRows.map((row) => [row.window_key, row]));
  const now = new Date();

  return {
    knower: Object.fromEntries(profileStatRanges.map((range) => {
      const row = knowerByRange.get(range);
      return [range, {
        totalPoints: row?.total_points ?? 0,
        percentile: row?.percentile ?? null,
        pickPoints: row?.pick_points ?? 0,
        likePoints: row?.like_points ?? 0,
      }];
    })) as ProfileHighlights["knower"],
    gamer: Object.fromEntries(profileStatRanges.map((range) => {
      const summary = summarizeMultiplayerProfileRange(matches, range, now);
      return [range, { gamesPlayed: summary.gamesPlayed, wins: summary.wins, winRate: summary.winRate }];
    })) as ProfileHighlights["gamer"],
  };
}

/** "October 2026", or "today" when the date is unknown. */
export function joinedMonth(date?: string): string {
  return date ? new Intl.DateTimeFormat("en", { month: "long", year: "numeric" }).format(new Date(date)) : "today";
}
