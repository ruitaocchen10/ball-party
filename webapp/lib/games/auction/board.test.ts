import { describe, expect, it } from "vitest";

import { matchupLine, weeklyRevealTier, type Lot } from "./board";

const weeklyLot = {
  position: "RB",
  season: 2018,
  week: 12,
  team: "KC",
  opponent: "NO",
} as Lot;

describe("matchupLine", () => {
  it("identifies the player's team before their opponent for a weekly lot", () => {
    expect(matchupLine(weeklyLot)).toBe("RB · 2018 · Week 12 · KC vs. NO");
  });

  it("keeps the team-only identity for a season-total lot", () => {
    expect(matchupLine({ ...weeklyLot, week: null, opponent: null })).toBe("RB · 2018 · KC");
  });
});

describe("weeklyRevealTier", () => {
  it("uses quarterback-specific PPR thresholds", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 14.9 })).toBe("rough");
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 15 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 25 })).toBe("great");
  });

  it("uses shared running back and receiver thresholds", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "RB", points: 9.9 })).toBe("rough");
    expect(weeklyRevealTier({ ...weeklyLot, position: "WR", points: 10 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "WR", points: 20 })).toBe("great");
  });

  it("recognizes a lower useful score for tight ends and leaves season lots neutral", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "TE", points: 8 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "TE", points: 16 })).toBe("great");
    expect(weeklyRevealTier({ ...weeklyLot, week: null, opponent: null, points: 150 })).toBeNull();
  });
});
