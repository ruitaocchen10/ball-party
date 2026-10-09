import { describe, expect, it } from "vitest";

import {
  asSoloBoard,
  boardHref,
  formatSoloScore,
  gamerStandingCopy,
  parseLeaderboardBoard,
  parseQbMode,
  soloBoardHref,
  soloStandingCopy,
} from "./boards";

describe("parseLeaderboardBoard / parseQbMode / asSoloBoard", () => {
  it("accepts known values and falls back on anything else", () => {
    expect(parseLeaderboardBoard("gamer")).toBe("gamer");
    expect(parseLeaderboardBoard(["gamer", "ball-knower"])).toBe("gamer");
    expect(parseLeaderboardBoard("nope")).toBe("ball-knower");
    expect(parseLeaderboardBoard("qb-season-builder")).toBe("ball-knower");
    expect(parseLeaderboardBoard(undefined)).toBe("ball-knower");
    expect(parseQbMode("hidden")).toBe("hidden");
    expect(parseQbMode("nope")).toBe("visible");
  });

  it("recognises a solo slug, so an old /leaderboard link can be sent to the game", () => {
    expect(asSoloBoard("higher-or-lower")).toBe("higher-or-lower");
    expect(asSoloBoard(["qb-season-builder"])).toBe("qb-season-builder");
    expect(asSoloBoard("gamer")).toBeNull();
    expect(asSoloBoard(undefined)).toBeNull();
  });
});

describe("boardHref", () => {
  it("leaves defaults out", () => {
    expect(boardHref({})).toBe("/leaderboard");
    expect(boardHref({ board: "ball-knower", window: "week" })).toBe("/leaderboard?window=week");
  });

  it("keeps board, window and scope", () => {
    expect(boardHref({ board: "gamer", window: "month", scope: "friends" })).toBe("/leaderboard?board=gamer&window=month&scope=friends");
  });
});

describe("soloBoardHref", () => {
  it("lives under the game and leaves defaults out", () => {
    expect(soloBoardHref({ board: "higher-or-lower" })).toBe("/solo/higher-or-lower/leaderboard");
    expect(soloBoardHref({ board: "higher-or-lower", scope: "friends" })).toBe("/solo/higher-or-lower/leaderboard?scope=friends");
  });

  it("only carries a QB mode on the QB board, and only when it is not the default", () => {
    expect(soloBoardHref({ board: "qb-season-builder", mode: "hidden" })).toBe("/solo/qb-season-builder/leaderboard?mode=hidden");
    expect(soloBoardHref({ board: "qb-season-builder", mode: "visible" })).toBe("/solo/qb-season-builder/leaderboard");
    expect(soloBoardHref({ board: "qb-season-builder", scope: "friends", mode: "hidden" })).toBe(
      "/solo/qb-season-builder/leaderboard?scope=friends&mode=hidden",
    );
    expect(soloBoardHref({ board: "higher-or-lower", mode: "hidden" })).toBe("/solo/higher-or-lower/leaderboard");
  });
});

describe("formatSoloScore", () => {
  it("shows a streak whole and a QB score with one decimal", () => {
    expect(formatSoloScore(1234, "higher-or-lower")).toBe("1,234");
    expect(formatSoloScore(91, "qb-season-builder")).toBe("91.0");
    expect(formatSoloScore(80.5, "qb-season-builder")).toBe("80.5");
  });
});

describe("standing copy", () => {
  it("explains an unranked caller", () => {
    expect(gamerStandingCopy({ status: "unranked", rank: null, wins: 0, gamesPlayed: 0, rankedCount: 4, minWins: 1 }).headline).toBe("Not ranked yet");
    expect(soloStandingCopy({ status: "unranked", rank: null, bestScore: null, rankedCount: 4 }).headline).toBe("Not ranked yet");
  });

  it("gives a top band on the everyone board and a plain rank among friends", () => {
    const standing = { status: "ranked", rank: 2, wins: 5, gamesPlayed: 9, rankedCount: 10, minWins: 1 } as const;
    expect(gamerStandingCopy(standing).detail).toBe("Top 20% of 10 ranked players");
    expect(gamerStandingCopy(standing, "friends").detail).toBe("Ranked 2 of 10 on your friends board");
  });
});
