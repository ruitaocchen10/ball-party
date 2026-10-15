import { describe, expect, it } from "vitest";

import { NFL_TEAM_CODES, benchTeams, biggestMoves, listPath, listTeamName, mergeByTime, movedCount, moveItem, placeChange, resizeTeams, sizeLabel } from "./lists";
import { nextSaveLabel, saveErrorMessage } from "./messages";

describe("moveItem", () => {
  it("puts an item at a place and shifts the ones between", () => {
    expect(moveItem(["a", "b", "c", "d"], 3, 1)).toEqual(["a", "d", "b", "c"]);
    expect(moveItem(["a", "b", "c", "d"], 0, 2)).toEqual(["b", "c", "a", "d"]);
  });

  it("leaves the list alone for a place outside it", () => {
    expect(moveItem(["a", "b"], 0, 5)).toEqual(["a", "b"]);
    expect(moveItem(["a", "b"], 1, 1)).toEqual(["a", "b"]);
  });
});

describe("placeChange and movedCount", () => {
  const before = ["BUF", "KC", "DET", "PHI"];
  const after = ["DET", "BUF", "KC", "SF"];

  it("counts places climbed, fallen or new", () => {
    expect(placeChange(before, after, 0)).toBe(2);
    expect(placeChange(before, after, 1)).toBe(-1);
    expect(placeChange(before, after, 3)).toBeNull();
    expect(placeChange(null, after, 0)).toBeNull();
  });

  it("counts the places that hold something different", () => {
    expect(movedCount(before, after)).toBe(4);
    expect(movedCount(before, before)).toBe(0);
    expect(movedCount(null, after)).toBe(4);
  });
});

describe("biggestMoves", () => {
  it("names new entries and the largest moves first", () => {
    const moves = biggestMoves(["BUF", "KC", "DET", "PHI"], ["DET", "BUF", "KC", "SF"], 3);
    expect(moves.map((move) => move.item)).toEqual(["SF", "DET", "BUF"]);
  });

  it("is empty with nothing to compare", () => {
    expect(biggestMoves(null, ["BUF"])).toEqual([]);
  });
});

describe("labels", () => {
  it("names teams and sizes", () => {
    expect(listTeamName("KC")).toBe("Kansas City Chiefs");
    expect(listTeamName("ZZZ")).toBe("ZZZ");
    expect(sizeLabel(32, "team")).toBe("All 32");
    expect(sizeLabel(10, "player")).toBe("Top 10");
  });

  it("builds list paths", () => {
    expect(listPath("qb")).toBe("/lists/qb");
    expect(listPath("qb", "maya")).toBe("/u/maya/lists/qb");
  });
});

describe("save errors", () => {
  const now = new Date("2026-10-14T12:00:00Z");

  it("says when the next save opens", () => {
    expect(nextSaveLabel("2026-10-14T15:00:00Z", now)).toBe("in 3 hours");
    expect(nextSaveLabel("2026-10-14T12:20:00Z", now)).toBe("in 20 minutes");
    expect(nextSaveLabel("nonsense", now)).toBeNull();
  });

  it("explains each rule in plain words", () => {
    expect(saveErrorMessage("edit_limit", "2026-10-14T15:00:00Z", now)).toContain("in 3 hours");
    expect(saveErrorMessage("prompt_open")).toContain("prompt");
    expect(saveErrorMessage("no_change")).toContain("same");
    expect(saveErrorMessage("something_else")).toBe("something_else");
  });
});

describe("team pool", () => {
  it("has 32 teams, each with a name", () => {
    expect(NFL_TEAM_CODES).toHaveLength(32);
    for (const code of NFL_TEAM_CODES) expect(listTeamName(code)).not.toBe(code);
  });

  it("benches the teams a list leaves out", () => {
    expect(benchTeams(["KC", "BUF"])).toHaveLength(30);
    expect(benchTeams(["KC", "BUF"])).not.toContain("KC");
  });

  it("cuts a list from the bottom and fills it from the bench", () => {
    expect(resizeTeams(["KC", "BUF", "DET"], 2)).toEqual(["KC", "BUF"]);
    expect(resizeTeams(["KC", "BUF"], 4)).toEqual(["KC", "BUF", "ARI", "ATL"]);
  });
});

describe("mergeByTime", () => {
  const item = (id: string, at: string) => ({ id, at });

  it("interleaves updates with the feed, newest first", () => {
    const merged = mergeByTime([item("p", "2026-10-08T10:00:00Z")], [item("u", "2026-10-08T12:00:00Z")], { before: null, floor: null });
    expect(merged.map((entry) => entry.id)).toEqual(["u", "p"]);
  });

  it("keeps updates inside the page window", () => {
    const updates = [item("new", "2026-10-09T00:00:00Z"), item("mid", "2026-10-07T00:00:00Z"), item("old", "2026-10-01T00:00:00Z")];
    const merged = mergeByTime([], updates, { before: "2026-10-08T00:00:00Z", floor: "2026-10-05T00:00:00Z" });
    expect(merged.map((entry) => entry.id)).toEqual(["mid"]);
  });
});
