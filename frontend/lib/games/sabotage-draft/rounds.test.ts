import { describe, expect, it } from "vitest";

import { ROUND_SLOTS, slotForRound } from "./rounds";

describe("sabotage draft round slots", () => {
  it("covers exactly the thirteen fixed roster slots", () => {
    expect(ROUND_SLOTS).toHaveLength(13);
  });

  it("maps round number to slot in deal order", () => {
    expect(slotForRound(1)).toBe("QB");
    expect(slotForRound(4)).toBe("WR1");
    expect(slotForRound(13)).toBe("ST");
  });

  it("has no fixed slot past round 13", () => {
    expect(slotForRound(14)).toBe("X_FACTOR");
  });
});
