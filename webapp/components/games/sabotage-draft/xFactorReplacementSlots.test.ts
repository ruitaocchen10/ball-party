import { describe, expect, it } from "vitest";

import { xFactorReplacementSlots } from "@/components/games/sabotage-draft/SabotageDraftMatch";

const pick = {
  match_id: "match",
  round_number: 14,
  user_id: "player",
  player_id: "player-id",
  display_name: "Player Name",
  season: 2025,
  by_timeout: false,
  headshot_url: null,
};

const options = (slot_category: string) => [{
  player_id: pick.player_id,
  display_name: pick.display_name,
  season: pick.season,
  slot_category,
  headshot_url: null,
}];

describe("xFactorReplacementSlots", () => {
  it.each([
    ["QB", ["QB"]],
    ["RB", ["RB1", "RB2"]],
    ["WR", ["WR1", "WR2", "WR3"]],
    ["TE", ["TE"]],
  ])("offers only matching slots for a %s X-Factor", (category, expected) => {
    expect(xFactorReplacementSlots(pick, options(category))).toEqual(expected);
  });

  it("offers no replacement slots until it can identify the X-Factor", () => {
    expect(xFactorReplacementSlots(pick, [])).toEqual([]);
  });
});
