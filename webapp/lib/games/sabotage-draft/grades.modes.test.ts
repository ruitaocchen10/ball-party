import { describe, expect, it } from "vitest";

import { gradeForPick, gradeForTeam } from "./grades";

describe("grades in the shorter modes", () => {
  it("grades a FLEX or DEF pick on the position the player actually plays", () => {
    // 13 AV is elite for a DL, merely average for a QB-scale scale; the slot
    // label alone would not say which distribution to read it against.
    expect(gradeForPick("DEF", 13, "DL")).toBe(gradeForPick("DL", 13));
    expect(gradeForPick("DEF", 13, "S")).toBe(gradeForPick("S", 13));
    expect(gradeForPick("FLEX", 9, "TE")).toBe(gradeForPick("TE", 9));
    expect(gradeForPick("FLEX", 9, "RB")).toBe(gradeForPick("RB", 9));
  });

  it("ignores the pick category for ordinary slots", () => {
    expect(gradeForPick("RB2", 7, "WR")).toBe(gradeForPick("RB1", 7));
  });

  it("grades a roster at its own mode's baseline like a full roster at 93", () => {
    expect(gradeForTeam(62, "standard")).toBe(gradeForTeam(93, "full"));
    expect(gradeForTeam(52, "quick")).toBe(gradeForTeam(93, "full"));
    expect(gradeForTeam(93)).toBe(gradeForTeam(93, "full"));
  });
});
