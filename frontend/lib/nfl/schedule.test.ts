import { describe, expect, it } from "vitest";

import { isPrimetimeKickoff, nflTeamFullName, parseNflSchedule } from "./schedule";

describe("parseNflSchedule", () => {
  it("expands team codes to their city and mascot for matchup copy", () => {
    expect(nflTeamFullName("CHI")).toBe("Chicago Bears");
    expect(nflTeamFullName("CAR")).toBe("Carolina Panthers");
  });

  it("keeps regular-season games and supplies real game identities", () => {
    const games = parseNflSchedule([
      "game_id,season,game_type,week,gameday,gametime,away_team,home_team,stadium",
      "2026_01_KC_BUF,2026,REG,1,2026-09-10,20:20,KC,BUF,Highmark Stadium",
      "2026_01_TEST,2026,POST,1,2026-09-10,20:20,KC,BUF,Highmark Stadium",
    ].join("\n"));

    expect(games).toEqual([expect.objectContaining({
      id: "2026_01_KC_BUF", season: 2026, week: 1, away: "KC", home: "BUF", label: "Chiefs @ Bills",
    })]);
    expect(games[0].kickoff).toBe("2026-09-11T00:20:00.000Z");
    expect(games[0].primetime).toBe(true);
    expect(games[0].stadium).toBe("Highmark Stadium");
  });

  it("converts Eastern Time through daylight saving time", () => {
    const games = parseNflSchedule([
      "game_id,season,game_type,week,gameday,gametime,away_team,home_team",
      "2026_15_KC_BUF,2026,REG,15,2026-12-13,13:00,KC,BUF",
    ].join("\n"));

    // December is EST (UTC-5), while the September fixture above is EDT
    // (UTC-4). A fixed offset would render one of them an hour wrong.
    expect(games[0].kickoff).toBe("2026-12-13T18:00:00.000Z");
  });
});

describe("isPrimetimeKickoff", () => {
  it("recognizes the national Thursday, Sunday, and Monday evening windows in Eastern time", () => {
    expect(isPrimetimeKickoff("2026-09-11T00:20:00.000Z")).toBe(true); // Thursday 8:20 PM EDT
    expect(isPrimetimeKickoff("2026-09-14T00:20:00.000Z")).toBe(true); // Sunday 8:20 PM EDT
    expect(isPrimetimeKickoff("2026-09-15T00:15:00.000Z")).toBe(true); // Monday 8:15 PM EDT
    expect(isPrimetimeKickoff("2026-09-13T17:00:00.000Z")).toBe(false); // Sunday 1:00 PM EDT
  });
});
