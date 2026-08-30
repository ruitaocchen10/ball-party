import { describe, expect, it } from "vitest";

import { completedMatchesFromHistory, recentMatches, summarizeMultiplayerProfile, summarizeProfile } from "@/lib/profile/summary";

describe("summarizeProfile", () => {
  it("calculates lifetime stats and sorts recent completed games", () => {
    const summary = summarizeProfile([
      { id: "one", game: "auction_team_builder", endedAt: "2026-08-10T14:00:00Z", placement: 2, rawScore: 67 },
      { id: "two", game: "auction_team_builder", endedAt: "2026-08-12T14:00:00Z", placement: 1, rawScore: 93 },
      { id: "three", game: "higher_or_lower", endedAt: "2026-08-11T14:00:00Z", placement: 1, rawScore: 12 },
    ]);

    expect(summary).toMatchObject({ gamesPlayed: 3, wins: 2, winRate: 67, bestStreak: 2 });
    expect(summary.recent.map((match) => match.id)).toEqual(["two", "three", "one"]);
  });

  it("uses zeroes when a player has not completed a match", () => {
    expect(summarizeProfile([])).toMatchObject({
      gamesPlayed: 0,
      wins: 0,
      winRate: 0,
      bestStreak: 0,
      recent: [],
    });
  });

  it("keeps solo results out of party win stats", () => {
    const summary = summarizeMultiplayerProfile([
      { id: "solo", game: "higher_or_lower", endedAt: "2026-08-10T14:00:00Z", placement: 1, rawScore: 12, mode: "solo" },
      { id: "party-loss", game: "higher_or_lower", endedAt: "2026-08-11T14:00:00Z", placement: 2, rawScore: 4, mode: "arcade" },
      { id: "party-win", game: "higher_or_lower", endedAt: "2026-08-12T14:00:00Z", placement: 1, rawScore: 8, mode: "arcade" },
    ]);

    expect(summary).toMatchObject({ gamesPlayed: 2, wins: 1, winRate: 50, bestStreak: 1 });
  });

  it("keeps completed history from past multiplayer lobbies in party stats", () => {
    const matches = completedMatchesFromHistory([
      { match_id: "old-lobby", game: "higher_or_lower", ended_at: "2026-08-10T14:00:00Z", placement: 2, raw_score: 4, mode: "arcade" },
      { match_id: "current-lobby", game: "higher_or_lower", ended_at: "2026-08-11T14:00:00Z", placement: 1, raw_score: 8, mode: "arcade" },
      { match_id: "solo", game: "higher_or_lower", ended_at: "2026-08-12T14:00:00Z", placement: 1, raw_score: 12, mode: "solo" },
    ]);

    expect(summarizeMultiplayerProfile(matches)).toMatchObject({ gamesPlayed: 2, wins: 1, winRate: 50 });
    expect(summarizeProfile(matches).recent.map((match) => match.id)).toEqual(["solo", "current-lobby", "old-lobby"]);
  });

  it("returns the newest results within each profile section", () => {
    const matches = [
      { id: "old", game: "higher_or_lower" as const, endedAt: "2026-08-10T14:00:00Z", placement: 2, rawScore: 4 },
      { id: "new", game: "higher_or_lower" as const, endedAt: "2026-08-12T14:00:00Z", placement: 1, rawScore: 8 },
    ];

    expect(recentMatches(matches, 1).map((match) => match.id)).toEqual(["new"]);
  });
});
