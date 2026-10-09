import { describe, expect, it } from "vitest";

import { MODE_SLOTS, chooseLabel, modeForRoundCount, rosterSlots, slotForRound, slotLabel, xFactorTargets } from "./rounds";

describe("sabotage draft round slots", () => {
  it("full mode is the original thirteen fixed slots plus the X-Factor", () => {
    expect(MODE_SLOTS.full).toHaveLength(14);
    expect(rosterSlots(14)).toHaveLength(13);
  });

  it("maps round number to slot in deal order", () => {
    expect(slotForRound(1)).toBe("QB");
    expect(slotForRound(4)).toBe("WR1");
    expect(slotForRound(13)).toBe("ST");
  });

  it("the last round is always the X-Factor", () => {
    expect(slotForRound(14)).toBe("X_FACTOR");
    expect(slotForRound(10, 10)).toBe("X_FACTOR");
    expect(slotForRound(7, 7)).toBe("X_FACTOR");
  });
});

describe("game modes", () => {
  it("recovers the mode from the round count", () => {
    expect(modeForRoundCount(14)).toBe("full");
    expect(modeForRoundCount(10)).toBe("standard");
    expect(modeForRoundCount(7)).toBe("quick");
  });

  it("deals standard and quick slots in order", () => {
    expect(rosterSlots(10)).toEqual(["QB", "RB1", "RB2", "WR1", "WR2", "TE", "FLEX", "DEF", "ST"]);
    expect(rosterSlots(7)).toEqual(["QB", "RB1", "WR1", "TE", "FLEX", "DEF"]);
    expect(slotForRound(5, 7)).toBe("FLEX");
    expect(slotForRound(6, 7)).toBe("DEF");
  });

  it("lets an X-Factor upgrade only skill slots its mode has", () => {
    expect(xFactorTargets("RB", 14)).toEqual(["RB1", "RB2"]);
    expect(xFactorTargets("WR", 7)).toEqual(["WR1", "FLEX"]);
    expect(xFactorTargets("TE", 10)).toEqual(["TE", "FLEX"]);
    expect(xFactorTargets("QB", 7)).toEqual(["QB"]);
    expect(xFactorTargets(undefined, 7)).toEqual([]);
  });

  it("labels the defensive slot", () => {
    expect(slotLabel("DEF")).toBe("Defensive Player");
    expect(chooseLabel("DEF")).toBe("a defensive player");
    expect(chooseLabel("FLEX")).toBe("an RB, WR or TE");
    expect(chooseLabel("RB2")).toBe("a RB");
  });
});
