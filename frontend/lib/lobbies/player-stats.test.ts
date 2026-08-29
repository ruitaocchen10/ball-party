import { describe, expect, it } from "vitest";

import { groupMatchHistoryByUser } from "./player-stats";

describe("groupMatchHistoryByUser", () => {
  it("groups multiple rows for the same user together", () => {
    const byUser = groupMatchHistoryByUser([
      { user_id: "a", match_id: "m1", game: "higher_or_lower", ended_at: "2026-01-01T00:00:00Z", placement: 1, raw_score: 10 },
      { user_id: "a", match_id: "m2", game: "higher_or_lower", ended_at: "2026-01-02T00:00:00Z", placement: 2, raw_score: 5 },
      { user_id: "b", match_id: "m3", game: "higher_or_lower", ended_at: "2026-01-01T00:00:00Z", placement: 1, raw_score: 10 },
    ]);
    expect(byUser.get("a")).toHaveLength(2);
    expect(byUser.get("b")).toHaveLength(1);
  });

  it("returns an empty map for no rows", () => {
    expect(groupMatchHistoryByUser([]).size).toBe(0);
  });

  it("drops rows with no ended_at, mirroring the profile page's own filter", () => {
    const byUser = groupMatchHistoryByUser([
      { user_id: "a", match_id: "m1", game: "higher_or_lower", ended_at: null, placement: null, raw_score: null },
    ]);
    expect(byUser.size).toBe(0);
  });
});
