import { describe, expect, it } from "vitest";

import { parseNflPlayers } from "./players";

describe("parseNflPlayers", () => {
  it("keeps active fantasy-position players and their current team", () => {
    // The header is nflverse's own: its release names the column `headshot`.
    const csv = [
      "gsis_id,display_name,position,latest_team,status,headshot",
      "00-1,Test Quarterback,QB,BUF,ACT,https://example.com/qb.jpg",
      "00-2,Inactive Back,RB,NYJ,RES,https://example.com/rb.jpg",
      "00-3,Active Kicker,K,KC,ACT,https://example.com/k.jpg",
    ].join("\n");

    expect(parseNflPlayers(csv)).toEqual([
      { id: "00-3", name: "Active Kicker", position: "K", team: "KC", headshotUrl: "https://example.com/k.jpg" },
      { id: "00-1", name: "Test Quarterback", position: "QB", team: "BUF", headshotUrl: "https://example.com/qb.jpg" },
    ]);
  });
});
