import { describe, expect, it } from "vitest";

import { summarizeProfile } from "@/lib/profile/summary";

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
});
