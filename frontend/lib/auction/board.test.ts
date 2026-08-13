import { describe, expect, it } from "vitest";

import { matchupLine, type Lot } from "./board";

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
