import { describe, expect, it } from "vitest";

import {
  DEFAULT_LEADERBOARD_SCOPE,
  DEFAULT_LEADERBOARD_WINDOW,
  LEADERBOARD_SCOPES,
  LEADERBOARD_WINDOWS,
  leaderboardHref,
  parseLeaderboardScope,
  parseLeaderboardWindow,
  standingCopy,
  topPercent,
} from "./windows";

describe("parseLeaderboardWindow", () => {
  it("accepts every window the RPC accepts", () => {
    for (const window of LEADERBOARD_WINDOWS) {
      expect(parseLeaderboardWindow(window)).toBe(window);
    }
  });

  it("falls back to the default for anything else", () => {
    expect(parseLeaderboardWindow(undefined)).toBe(DEFAULT_LEADERBOARD_WINDOW);
    expect(parseLeaderboardWindow("decade")).toBe(DEFAULT_LEADERBOARD_WINDOW);
    expect(parseLeaderboardWindow("")).toBe(DEFAULT_LEADERBOARD_WINDOW);
  });

  it("uses the first value when the param is repeated", () => {
    expect(parseLeaderboardWindow(["month", "year"])).toBe("month");
    expect(parseLeaderboardWindow(["decade", "year"])).toBe(DEFAULT_LEADERBOARD_WINDOW);
  });
});

describe("parseLeaderboardScope", () => {
  it("accepts every scope the RPC accepts", () => {
    for (const scope of LEADERBOARD_SCOPES) expect(parseLeaderboardScope(scope)).toBe(scope);
  });

  it("falls back to everyone for anything else", () => {
    expect(parseLeaderboardScope(undefined)).toBe(DEFAULT_LEADERBOARD_SCOPE);
    expect(parseLeaderboardScope("enemies")).toBe(DEFAULT_LEADERBOARD_SCOPE);
    expect(parseLeaderboardScope(["friends", "all"])).toBe("friends");
  });
});

describe("leaderboardHref", () => {
  it("keeps the window when the scope changes, and omits the default scope", () => {
    expect(leaderboardHref("month", "all")).toBe("/leaderboard?window=month");
    expect(leaderboardHref("month", "friends")).toBe("/leaderboard?window=month&scope=friends");
  });
});

describe("standingCopy in the friends scope", () => {
  it("reports a plain rank among friends instead of a percentile", () => {
    const standing = { status: "ranked", rank: 2, totalPoints: 40, scoredPicks: 9, rankedCount: 5, minPicks: 5 } as const;
    expect(standingCopy(standing, "friends").detail).toBe("Ranked 2 of 5 on your friends board");
  });
});

describe("topPercent", () => {
  it("rounds up so a player is never shown a better band than they hold", () => {
    expect(topPercent(1, 1000)).toBe(1);
    expect(topPercent(211, 1316)).toBe(17);
    expect(topPercent(1316, 1316)).toBe(100);
  });

  it("is null when there is nobody to compare against", () => {
    expect(topPercent(1, 0)).toBeNull();
  });
});

describe("standingCopy", () => {
  const base = { rank: null, totalPoints: 0, scoredPicks: 0, rankedCount: 10, minPicks: 3 };

  it("names the rank and band for a ranked player", () => {
    expect(standingCopy({ ...base, status: "ranked", rank: 2, totalPoints: 30, scoredPicks: 4, rankedCount: 20 })).toEqual({
      headline: "#2",
      detail: "Top 10% of 20 ranked players",
    });
  });

  it("says how many picks are missing for an unranked player", () => {
    expect(standingCopy({ ...base, status: "unranked", scoredPicks: 1 })).toEqual({
      headline: "Not ranked yet",
      detail: "2 more scored picks to join the board",
    });
    expect(standingCopy({ ...base, status: "unranked", scoredPicks: 2 }).detail).toBe("1 more scored pick to join the board");
  });
});
