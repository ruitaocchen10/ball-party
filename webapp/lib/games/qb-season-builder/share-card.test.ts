import { describe, expect, it } from "vitest";

import { shareCardFromResult } from "@/lib/games/qb-season-builder/share-card";
import type { SeasonResult } from "@/lib/games/qb-season-builder/result";

const result: SeasonResult = {
  matchId: "22222222-2222-2222-2222-222222222222",
  mode: "hidden",
  statLine: { attempts: 598, completions: 412, passYards: 5104, passTds: 44, interceptions: 9, rating: 108.3, rushYards: 312, rushTds: 4 },
  record: { wins: 13, losses: 4 },
  playoffs: { depth: 4, result: "lost_super_bowl" },
  awards: { mvp: true, opoy: false, all_pro: true, pro_bowl: true, sb_mvp: false },
  score: 88.4,
  breakdown: [],
  closestSeason: { franchiseCode: "den", season: 2013, displayName: "Peyton Manning", passYards: 5477, passTds: 55, interceptions: 10, wins: 13, losses: 3 },
  picks: [],
};

describe("shareCardFromResult", () => {
  it("puts a completed season's headline stats, outcome, awards, and score on its public card", () => {
    expect(shareCardFromResult(result)).toEqual({
      title: "QB Season Builder",
      description: "5,104 pass yards · 44 pass TD · 9 INT · 13–4 · Lost the Super Bowl · MVP, First-Team All-Pro, Pro Bowl · 88.4 score",
      statLine: "5,104 YDS · 44 TD · 9 INT",
      record: "13–4 RECORD",
      playoffs: "Lost the Super Bowl",
      awards: ["MVP", "First-Team All-Pro", "Pro Bowl"],
      score: "88.4",
    });
  });

  it("does not include mode, source ratings, or draft-option values", () => {
    const card = shareCardFromResult({
      ...result,
      // These are intentionally not part of SeasonResult. Simulate private
      // fields appearing on a runtime object: the public-card boundary must
      // still ignore them.
      ...({ mode: "hidden", sourceRating: 99, draftOptions: { accuracy: 91 } } as object),
    });

    expect(JSON.stringify(card).toLowerCase()).not.toMatch(/hidden|madden|sourcerating|draftoptions|accuracy/);
  });
});
