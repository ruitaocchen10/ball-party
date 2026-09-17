import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";

import { PromptPostComposer, PromptPostFeed } from "./PromptPostUI";
import type { Post } from "@/lib/foundation/content/prompts/types";

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
  const { rerender } = render(<PromptPostFeed posts={[post([chiefsAtBills])]} viewerCanAnswer onSelectPost={() => {}} gameContexts={gameContexts} />);

  expect(screen.getByTestId("single-game-matchup-preview")).toHaveStyle({ clipPath: expect.stringContaining("polygon") });
  expect(screen.getByText("Primetime")).toBeInTheDocument();
  expect(screen.getByText("Highmark Stadium")).toBeInTheDocument();
  expect(screen.getByText(/8:20 PM/)).toBeInTheDocument();

  rerender(<PromptPostFeed posts={[post([chiefsAtBills, {
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

it("marking a picks post as opinion publishes it without an auto-resolve source", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{
    id: "2026_01_KC_BUF",
    season: 2026,
    week: 1,
    kickoff: "2099-09-11T00:20:00.000Z",
    away: "KC",
    home: "BUF",
    label: "Chiefs @ Bills",
    stadium: "Highmark Stadium",
    primetime: true,
  }];

  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: /Opinion — no correct answer, no points/ }));
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  expect(onPublish).toHaveBeenCalledTimes(1);
  const published = onPublish.mock.calls[0][0];
  expect(published.isOpinion).toBe(true);
  expect(published.resolutionSource).toBeUndefined();
});

it("publishes the point value configured for each slot", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{
    id: "2026_01_KC_BUF",
    season: 2026,
    week: 1,
    kickoff: "2099-09-11T00:20:00.000Z",
    away: "KC",
    home: "BUF",
    label: "Chiefs @ Bills",
    stadium: "Highmark Stadium",
    primetime: true,
  }];

  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.clear(screen.getByLabelText("Chiefs @ Bills — winner points"));
  await user.type(screen.getByLabelText("Chiefs @ Bills — winner points"), "42");
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  expect(onPublish).toHaveBeenCalledTimes(1);
  expect(onPublish.mock.calls[0][0].slots[0].points).toBe(42);
});
