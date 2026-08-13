import type { MatchGame } from "@/lib/games/catalog";

export type CompletedMatch = {
  id: string;
  game: MatchGame;
  endedAt: string;
  placement: number | null;
  rawScore: number | null;
};

export type ProfileSummary = {
  gamesPlayed: number;
  wins: number;
  winRate: number;
  bestStreak: number;
  recent: CompletedMatch[];
};

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
    recent: [...oldestFirst].reverse().slice(0, 3),
  };
}
