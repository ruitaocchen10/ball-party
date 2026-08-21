import { describe, expect, it } from "vitest";

import { GAMES } from "./catalog";

describe("home game catalog", () => {
  it("advertises Higher or Lower as a live simultaneous game", () => {
    expect(GAMES.find((game) => game.slug === "higher-or-lower")).toMatchObject({
      match: "higher_or_lower",
      tagline: "Everyone calls higher or lower at once. Longest streak wins.",
      players: "2–4 players",
      duration: "3–5 min",
      status: "live",
      kind: "Group · simultaneous",
      solo: true,
    });
  });

  it("keeps Auction Team Builder as the only featured game", () => {
    expect(GAMES.filter((game) => game.featured)).toHaveLength(1);
    expect(GAMES.find((game) => game.slug === "auction-team-builder")?.featured).toBe(true);
  });
});
