import { describe, expect, it } from "vitest";

import { joinedMonth, profileHighlights } from "./highlights";

describe("profileHighlights", () => {
  it("fills every window, defaulting missing knower rows to zero and unranked", () => {
    const highlights = profileHighlights([], [{ window_key: "lifetime", total_points: 42, percentile: 80, pick_points: 40, like_points: 2 }]);
    expect(highlights.knower.lifetime).toEqual({ totalPoints: 42, percentile: 80, pickPoints: 40, likePoints: 2 });
    expect(highlights.knower.week).toEqual({ totalPoints: 0, percentile: null, pickPoints: 0, likePoints: 0 });
    expect(highlights.gamer.lifetime.gamesPlayed).toBe(0);
  });

  it("names the join month, or today when unknown", () => {
    expect(joinedMonth("2026-03-15T00:00:00Z")).toMatch(/2026/);
    expect(joinedMonth(undefined)).toBe("today");
  });
});
