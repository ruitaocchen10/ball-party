import { render, screen } from "@testing-library/react";
import { expect, it } from "vitest";

import { TakeResponse, crowdTopFiveMatches } from "./TakeResponse";
import type { Post } from "@/lib/foundation/content/prompts/types";

it("counts the crowd's top-five teams that a ballot also ranks in its own top five", () => {
  expect(crowdTopFiveMatches(["a", "b", "c", "d", "e"], ["a", "x", "c", "y", "z", "b"])).toBe(2);
  expect(crowdTopFiveMatches([], ["a"])).toBe(0);
});

it("sums up a power rankings ballot against the crowd's top five", () => {
  const options = ["a", "b", "c", "d", "e", "f"].map((id) => ({ id, label: id.toUpperCase(), teamCode: id.toUpperCase() }));
  const post = {
    id: "p", templateKind: "power_rankings", templateName: "Power Rankings", isOpinion: true,
    slots: [{ id: "s", label: "Rank", shape: "rank", points: 0, options }],
    powerRankingTopFive: ["a", "b", "c", "d", "e"].map((optionId, i) => ({ optionId, topFiveCount: 9 - i, averageRank: i + 1 })),
    previousRankByTeam: {},
  } as unknown as Post;
  render(<TakeResponse post={post} response={{ s: ["a", "f", "c", "b", "e", "d"] }} />);
  expect(screen.getByText("matched 4 of 5")).toBeInTheDocument();
});
