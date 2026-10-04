import { expect, it } from "vitest";

import { describeTarget } from "@/lib/foundation/content/prompts/boldPredictions";
import { INDEXABLE_TEMPLATE_KINDS } from "@/lib/foundation/content/prompts/meta";
import { promptErrorMessage } from "@/lib/foundation/content/prompts/messages";

const data = {
  weekGames: [{ id: "g1", season: 2026, week: 5, kickoff: "2026-10-08T00:00:00Z", away: "BUF", home: "KC", label: "Bills @ Chiefs", stadium: "", primetime: false }],
  players: { p1: { id: "p1", name: "Josh Allen", position: "QB", team: "BUF", headshotUrl: null, status: "ACT" } },
};

it("describes each tag kind with its name and art", () => {
  expect(describeTarget({ type: "team", id: "GB" }, data)).toMatchObject({ label: "Packers", teamCodes: ["GB"] });
  expect(describeTarget({ type: "matchup", id: "g1" }, data)).toMatchObject({ label: "Bills @ Chiefs", teamCodes: ["BUF", "KC"] });
  expect(describeTarget({ type: "player", id: "p1" }, data)).toMatchObject({ label: "Josh Allen", teamCodes: [] });
});

it("still labels a tag it cannot resolve", () => {
  expect(describeTarget({ type: "player", id: "gone" }, data).label).toBe("Player");
  expect(describeTarget({ type: "matchup", id: "gone" }, data).label).toBe("Matchup");
});

it("explains the errors the prediction RPCs raise", () => {
  expect(promptErrorMessage("too_many_predictions")).toMatch(/five predictions/);
  expect(promptErrorMessage("invalid_target")).toMatch(/tag/);
  expect(promptErrorMessage("post_locked")).toMatch(/locked/);
});

it("lists Bold Predictions in the sitemap kinds", () => {
  expect(INDEXABLE_TEMPLATE_KINDS).toContain("bold_predictions");
});
