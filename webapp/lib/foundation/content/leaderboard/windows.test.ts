import { describe, expect, it } from "vitest";

import {
  DEFAULT_LEADERBOARD_WINDOW,
  LEADERBOARD_WINDOWS,
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

  it("points a hidden player to settings", () => {
    expect(standingCopy({ ...base, status: "hidden", totalPoints: 90 })).toEqual({
      headline: "You're hidden",
      detail: "Turn rankings visibility back on in Settings to appear here",
    });
  });
});
