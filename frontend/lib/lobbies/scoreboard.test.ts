import { describe, expect, it } from "vitest";

import { tallyWins } from "./scoreboard";

describe("tallyWins", () => {
  it("counts one win per row for its user", () => {
    const wins = tallyWins([{ user_id: "a" }, { user_id: "b" }, { user_id: "a" }]);
    expect(wins.get("a")).toBe(2);
    expect(wins.get("b")).toBe(1);
  });

  it("returns an empty tally for no rows", () => {
    expect(tallyWins([]).size).toBe(0);
  });
});
