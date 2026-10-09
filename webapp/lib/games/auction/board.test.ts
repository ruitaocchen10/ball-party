import { describe, expect, it } from "vitest";

import { matchupLine, myScoutHint, playableLotCount, tokensRemaining, wasPresented, upsertLot, weeklyRevealTier, type AuctionFormat, type Lot, type ScoutHint } from "./board";

const weeklyLot = {
  position: "RB",
  season: 2018,
  week: 12,
  team: "KC",
  opponent: "NO",
} as Lot;

describe("matchupLine", () => {
  it("identifies the player's team before their opponent for a weekly lot", () => {
    expect(matchupLine(weeklyLot)).toBe("RB · 2018 · Week 12 · KC vs. NO");
  });

  it("keeps the team-only identity for a season-total lot", () => {
    expect(matchupLine({ ...weeklyLot, week: null, opponent: null })).toBe("RB · 2018 · KC");
  });
});

describe("weeklyRevealTier", () => {
  it("uses quarterback-specific PPR thresholds", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 14.9 })).toBe("rough");
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 15 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "QB", points: 25 })).toBe("great");
  });

  it("uses shared running back and receiver thresholds", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "RB", points: 9.9 })).toBe("rough");
    expect(weeklyRevealTier({ ...weeklyLot, position: "WR", points: 10 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "WR", points: 20 })).toBe("great");
  });

  it("recognizes a lower useful score for tight ends and leaves season lots neutral", () => {
    expect(weeklyRevealTier({ ...weeklyLot, position: "TE", points: 8 })).toBe("solid");
    expect(weeklyRevealTier({ ...weeklyLot, position: "TE", points: 16 })).toBe("great");
    expect(weeklyRevealTier({ ...weeklyLot, week: null, opponent: null, points: 150 })).toBeNull();
  });
});

describe("tokensRemaining", () => {
  const format = { tokenCount: 2 } as AuctionFormat;
  const fresh = { used_pass_token: false, used_scout_token: false, used_seal_token: false };

  it("is the match's token budget when nothing has been spent", () => {
    expect(tokensRemaining(format, fresh)).toBe(2);
  });

  it("counts a spend against the shared budget regardless of which ability it was", () => {
    expect(tokensRemaining(format, { ...fresh, used_scout_token: true })).toBe(1);
  });

  it("floors at zero once every ability has been used, even past the budget", () => {
    expect(tokensRemaining(format, { used_pass_token: true, used_scout_token: true, used_seal_token: true })).toBe(0);
  });

  it("is zero with no format or no seat, matching a match dealt before tokens existed", () => {
    expect(tokensRemaining(null, fresh)).toBe(0);
    expect(tokensRemaining(format, null)).toBe(0);
  });
});

describe("myScoutHint", () => {
  const hints: ScoutHint[] = [
    { match_id: "m", seq: 1, user_id: "u0", tier: "solid", created_at: "" },
    { match_id: "m", seq: 2, user_id: "u1", tier: "great", created_at: "" },
  ];

  it("finds the viewer's own hint for the lot in question", () => {
    expect(myScoutHint(hints, 1, "u0")?.tier).toBe("solid");
  });

  it("never returns another player's hint, even for the same lot", () => {
    expect(myScoutHint(hints, 2, "u0")).toBeNull();
  });

  it("is null for a lot nobody has scouted yet", () => {
    expect(myScoutHint(hints, 3, "u0")).toBeNull();
  });
});

describe("upsertLot", () => {
  const at = (seq: number, display_name = "P") => ({ ...weeklyLot, seq, display_name }) as Lot;

  it("replaces the lot with the same seq in place", () => {
    const out = upsertLot([at(1), at(2)], at(2, "Updated"));
    expect(out.map((l) => l.display_name)).toEqual(["P", "Updated"]);
  });

  it("appends a lot the client has never seen, which is what a declined lot's redraw is", () => {
    const out = upsertLot([at(1), at(2)], at(3, "Redrawn"));
    expect(out.map((l) => l.seq)).toEqual([1, 2, 3]);
  });

  it("keeps seq order when a late lot arrives out of order", () => {
    expect(upsertLot([at(1), at(3)], at(2)).map((l) => l.seq)).toEqual([1, 2, 3]);
  });
});

describe("playableLotCount", () => {
  const standard = {
    scoringMode: "weekly", rosterPreset: "standard", qbSlots: 1, rbSlots: 1, wrSlots: 1, teSlots: 1,
    flexSlots: 1, purse: 25, seasonFrom: 2010, seasonTo: 2025, tokenCount: 0,
  } as AuctionFormat;
  const four = ["a", "b", "c", "d"].map((user_id) => ({ user_id }));
  const at = (seq: number, over: Partial<Lot> = {}) => ({ seq, position: "RB", winner_id: null, slot: null, ...over }) as Lot;
  const turn = (currentLot: number, phase: "bidding" | "sold" = "bidding") => ({ lotCount: 22, currentLot, phase });

  it("drops the FLEX spares from the opening count", () => {
    // Four players, five slots each: 20 lots to play out of the 22 dealt.
    expect(playableLotCount(turn(1), [at(1)], four, standard)).toBe(20);
  });

  it("is the lots behind the table, the one on the block, and the slots still open", () => {
    const lots = [
      at(1, { winner_id: "a", slot: "RB" }),
      at(2, { winner_id: "b", slot: "QB" }),
      at(3),
    ];
    // Two slots filled, so 18 open; lot 3 is on the block and fills one of them.
    expect(playableLotCount(turn(3), lots, four, standard)).toBe(3 + 17);
  });

  it("counts a sold current lot as already filled, not still ahead", () => {
    const lots = [at(1, { winner_id: "a", slot: "RB" })];
    expect(playableLotCount(turn(1, "sold"), lots, four, standard)).toBe(1 + 19);
  });

  it("lands exactly on the last lot when only it is left", () => {
    const won = ["a", "b", "c", "d"].flatMap((id, i) =>
      ["QB", "RB", "WR", "TE", "FLEX"].map((slot, j) => at(i * 5 + j + 1, { winner_id: id, slot })),
    );
    // Everyone is full but the last seat's FLEX, which is the lot on the block.
    const last = won.pop()!;
    expect(playableLotCount(turn(20), [...won, at(20, { position: last.position })], four, standard)).toBe(20);
  });

  it("never exceeds what the server dealt", () => {
    expect(playableLotCount({ lotCount: 6, currentLot: 1, phase: "bidding" }, [at(1)], four, standard)).toBe(6);
  });

  it("falls back to the original five-slot shape for a board with no format", () => {
    expect(playableLotCount(turn(1), [at(1)], four, null)).toBe(20);
  });

  it("sizes a Deep board from its own slot counts", () => {
    const deep = { ...standard, rosterPreset: "deep", qbSlots: 2, rbSlots: 2, wrSlots: 3, flexSlots: 2 } as AuctionFormat;
    expect(playableLotCount({ lotCount: 40, currentLot: 1, phase: "bidding" }, [at(1)], four, deep)).toBe(40);
  });
});

describe("wasPresented", () => {
  it("is true for any lot the server settled, sold or not", () => {
    expect(wasPresented({ resolved_at: "2026-09-24T12:00:00Z" })).toBe(true);
  });

  it("is false for a spare the dealer skipped, which was never resolved", () => {
    expect(wasPresented({ resolved_at: null })).toBe(false);
  });
});
