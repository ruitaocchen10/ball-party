import type { MatchGame } from "@/lib/platform/orchestration/catalog";

export type CompletedMatch = {
  id: string;
  game: MatchGame;
  endedAt: string;
  placement: number | null;
  rawScore: number | null;
};

/** A completed match paired with the mode of the run that created it. */
export type CompletedMatchWithMode = CompletedMatch & {
  mode: "arcade" | "party" | "solo";
};

export type ProfileHistoryRow = {
  match_id: string | null;
  game: string | null;
  ended_at: string | null;
  placement: number | null;
  raw_score: number | null;
  mode: "arcade" | "party" | "solo" | null;
};

/** Turns the self-only history RPC's database-shaped rows into app records. */
export function completedMatchesFromHistory(rows: ProfileHistoryRow[]): CompletedMatchWithMode[] {
  return rows.flatMap((row) => {
    if (!row.match_id || !row.game || !row.ended_at || !row.mode) return [];
    return [{
      id: row.match_id,
      game: row.game as MatchGame,
      endedAt: row.ended_at,
      placement: row.placement,
      rawScore: row.raw_score,
      mode: row.mode,
    }];
  });
}

export type ProfileSummary = {
  gamesPlayed: number;
  wins: number;
  winRate: number;
  bestStreak: number;
  recent: CompletedMatch[];
};

export const profileStatRanges = ["lifetime", "year", "month", "week"] as const;
export type ProfileStatRange = (typeof profileStatRanges)[number];

/** Uses rolling windows so a player's reporting period is always current. */
export function matchesInProfileRange(
  matches: CompletedMatchWithMode[],
  range: ProfileStatRange,
  now = new Date(),
): CompletedMatchWithMode[] {
  if (range === "lifetime") return matches;

  const days = range === "year" ? 365 : range === "month" ? 30 : 7;
  const startsAt = now.getTime() - days * 24 * 60 * 60 * 1000;
  return matches.filter((match) => new Date(match.endedAt).getTime() >= startsAt);
}

/** The newest first, capped for a compact profile section. */
export function recentMatches<T extends CompletedMatch>(matches: T[], limit = 3): T[] {
  return [...matches].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit);
}

/**
 * Converts the platform's per-match records into the handful of facts a
 * profile needs. It deliberately only accepts completed matches: setup and
 * abandoned games are sessions a player entered, not games they played.
 */
export function summarizeProfile(matches: CompletedMatch[]): ProfileSummary {
  const oldestFirst = [...matches].sort((a, b) => a.endedAt.localeCompare(b.endedAt));
  const wins = oldestFirst.filter((match) => match.placement === 1).length;

  let bestStreak = 0;
  let currentStreak = 0;
  for (const match of oldestFirst) {
    if (match.placement === 1) {
      currentStreak += 1;
      bestStreak = Math.max(bestStreak, currentStreak);
    } else {
      currentStreak = 0;
    }
  }

  return {
    gamesPlayed: oldestFirst.length,
    wins,
    winRate: oldestFirst.length === 0 ? 0 : Math.round((wins / oldestFirst.length) * 100),
    bestStreak,
    recent: recentMatches(oldestFirst),
  };
}

/**
 * Multiplayer wins are a separate measure from a solo score. Solo matches
 * still belong in the player's history, but there is no opponent to beat.
 */
export function summarizeMultiplayerProfile(matches: CompletedMatchWithMode[]): ProfileSummary {
  return summarizeProfile(matches.filter((match) => match.mode !== "solo"));
}

export function summarizeMultiplayerProfileRange(
  matches: CompletedMatchWithMode[],
  range: ProfileStatRange,
  now?: Date,
): ProfileSummary {
  return summarizeMultiplayerProfile(matchesInProfileRange(matches, range, now));
}
