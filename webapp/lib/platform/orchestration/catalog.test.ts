import { describe, expect, it } from "vitest";

import { GAMES, groupGames, matchGameName, soloGames, startableGames } from "./catalog";

describe("home game catalog", () => {
  it("lists QB Season Builder as a live one-player game a solo run can start", () => {
    expect(GAMES.find((game) => game.slug === "qb-season-builder")).toMatchObject({
      match: "qb_season_builder",
      players: "1 player",
      status: "live",
      solo: true,
    });
    expect(soloGames()).toContain("qb_season_builder");
    expect(matchGameName("qb_season_builder")).toBe("QB Season Builder");
  });

  it("keeps a solo-only game out of every room-facing list", () => {
    expect(startableGames()).not.toContain("qb_season_builder");
    expect(startableGames()).toContain("higher_or_lower");
    expect(groupGames().map((game) => game.slug)).not.toContain("qb-season-builder");
  });

  it("advertises Higher or Lower as a live simultaneous game", () => {
    expect(GAMES.find((game) => game.slug === "higher-or-lower")).toMatchObject({
      match: "higher_or_lower",
      tagline: "Everyone calls higher or lower at once. Longest streak wins.",
      players: "2–4 players",
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
