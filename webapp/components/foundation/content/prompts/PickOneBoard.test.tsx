import { render, screen, within } from "@testing-library/react";
import { expect, it } from "vitest";

import { PromptPostFeed } from "./PromptPostUI";
import type { Option, Post } from "@/lib/foundation/content/prompts/types";

const UPLOAD = "https://static.www.nfl.com/image/upload/f_auto,q_auto/league";

const NAMES = ["Saquon Barkley", "Derrick Henry", "Jahmyr Gibbs", "Bijan Robinson", "Breece Hall", "James Cook"];
const pool = (count: number, placed: Record<number, number> = {}): Option[] =>
  NAMES.slice(0, count).map((name, index) => ({ id: `rb-${index + 1}`, label: name, sublabel: "PHI", teamCode: "PHI", headshotUrl: `${UPLOAD}/id${index}`, ...(placed[index + 1] ? { coverPosition: placed[index + 1] } : {}) }));

function leaderPost(options: Option[]): Post {
  return {
    id: "leader",
    templateKind: "stat_leader",
    templateName: "Pick one out of these",
    author: "Ball Party",
    caption: "Settle it.",
    createdAt: "2026-09-01T12:00:00.000Z",
    promptText: "Who leads the NFL in rushing?",
    resolutionCriteria: "Most yards after Week 18.",
    lockAt: "2099-09-20T12:00:00.000Z",
    status: "open",
    slots: [{ id: "slot", label: "Leader", shape: "pick", points: 25, options }],
    comments: [],
    responseCount: 0,
    viewerAnswered: false,
  };
}

it.each([[2], [3], [4]])("draws %i candidates side by side as faces, not the old row of icons", (count) => {
  const { container } = render(<PromptPostFeed posts={[leaderPost(pool(count))]} viewerCanAnswer onSelectPost={() => {}} />);

  const art = within(screen.getByTestId("pick-one-board"));
  expect(art.getAllByText("PHI")).toHaveLength(count);
  // A resized headshot per player, and no "+N" overflow chip.
  expect(container.querySelectorAll('img[src*="f_png,q_auto"]')).toHaveLength(count);
  expect(screen.queryByText(/\+\d+ more/)).not.toBeInTheDocument();
  expect(screen.getByTestId("pick-one-board").firstElementChild).toHaveClass("flex");
});

it("shows the admin's four art players, in their order, and says how many more are in the pool", () => {
  // Hall, Henry, Cook, Barkley placed 1–4; Gibbs and Robinson stay in the pool only.
  render(<PromptPostFeed posts={[leaderPost(pool(6, { 5: 1, 2: 2, 6: 3, 1: 4 }))]} viewerCanAnswer onSelectPost={() => {}} />);

  const text = screen.getByTestId("pick-one-board").textContent ?? "";
  expect(text).not.toContain("Gibbs");
  expect(text).not.toContain("Robinson");
  const positions = ["Hall", "Henry", "Cook", "Barkley"].map((surname) => text.indexOf(surname));
  expect(positions.every((position) => position >= 0)).toBe(true);
  expect(positions).toEqual([...positions].sort((left, right) => left - right));
  expect(screen.getByText("+2 more to choose from")).toBeInTheDocument();
});

it("falls back to the first four for a bigger pool published before the art could be chosen", () => {
  render(<PromptPostFeed posts={[leaderPost(pool(6))]} viewerCanAnswer onSelectPost={() => {}} />);

  const text = screen.getByTestId("pick-one-board").textContent ?? "";
  expect(text).toContain("Robinson");
  expect(text).not.toContain("Hall");
  expect(screen.getByText("+2 more to choose from")).toBeInTheDocument();
});

it("shows initials for a candidate with no headshot", () => {
  const options = pool(2).map((option, index) => (index === 0 ? { ...option, headshotUrl: undefined } : option));
  render(<PromptPostFeed posts={[leaderPost(options)]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(within(screen.getByTestId("pick-one-board")).getByText("SB")).toBeInTheDocument();
});
