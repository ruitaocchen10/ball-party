import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it } from "vitest";

import { VariantCFeed } from "./VariantC";
import type { Post } from "./types";

function post(slots: Post["slots"]): Post {
  return {
    id: "post",
    templateKind: "picks",
    templateName: "Picks",
    author: "Ball Party",
    caption: "Make the call.",
    createdAt: "2026-09-01T12:00:00.000Z",
    promptText: "Week 1 picks",
    resolutionCriteria: "Final score wins.",
    lockAt: "2026-09-20T12:00:00.000Z",
    status: "open",
    slots,
    comments: [],
    responseCount: 3,
    viewerAnswered: false,
  };
}

const chiefsAtBills = {
  id: "chiefs-bills",
  label: "Chiefs @ Bills",
  shape: "pick" as const,
  points: 1,
  sourceGameId: "2026_01_KC_BUF",
  options: [
    { id: "kc", label: "Chiefs", teamCode: "KC" },
    { id: "buf", label: "Bills", teamCode: "BUF" },
  ],
};

it("gives a single matchup its own poster treatment and lets a weekly set page through posters", async () => {
  const user = userEvent.setup();
  const gameContexts = [{ id: "2026_01_KC_BUF", stadium: "Highmark Stadium", kickoff: "2026-09-11T00:20:00.000Z", primetime: true }];
  const { rerender } = render(<VariantCFeed posts={[post([chiefsAtBills])]} viewerCanAnswer onSelectPost={() => {}} gameContexts={gameContexts} />);

  expect(screen.getByTestId("single-game-matchup-preview")).toHaveStyle({ clipPath: expect.stringContaining("polygon") });
  expect(screen.getByText("Primetime")).toBeInTheDocument();
  expect(screen.getByText("Highmark Stadium")).toBeInTheDocument();
  expect(screen.getByText(/8:20 PM/)).toBeInTheDocument();

  rerender(<VariantCFeed posts={[post([chiefsAtBills, {
    ...chiefsAtBills,
    id: "ravens-bengals",
    label: "Ravens @ Bengals",
    options: [
      { id: "bal", label: "Ravens", teamCode: "BAL" },
      { id: "cin", label: "Bengals", teamCode: "CIN" },
    ],
  }])]} viewerCanAnswer onSelectPost={() => {}} gameContexts={gameContexts} />);

  expect(screen.queryByTestId("single-game-matchup-preview")).not.toBeInTheDocument();
  expect(screen.getByTestId("multi-game-matchup-preview")).toBeInTheDocument();
  expect(screen.getByLabelText("Showing matchup 1 of 2")).toBeInTheDocument();
  expect(screen.getByText("Chiefs")).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Next matchup" }));

  expect(screen.getByLabelText("Showing matchup 2 of 2")).toBeInTheDocument();
  expect(screen.getByText("Ravens")).toBeInTheDocument();
});
