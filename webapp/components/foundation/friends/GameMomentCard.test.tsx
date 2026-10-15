import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { groupActivity, type ActivityEvent } from "@/lib/foundation/friends/friends";
import { GameMomentCard, beatLine } from "./GameMomentCard";

const base: ActivityEvent = {
  type: "win",
  occurredAt: "2026-10-08T10:00:00Z",
  actorId: "a1",
  username: "ava",
  displayName: "Ava",
  avatarUrl: null,
  matchId: null,
  game: null,
  placement: null,
  rawScore: null,
  runMode: null,
  mode: null,
  opponents: [],
  opponentYou: false,
  opponentCount: 0,
  friendRank: null,
  friendCount: null,
};

const cards = (events: ActivityEvent[]) =>
  render(<ol>{groupActivity(events).map((item, index) => <li key={index}><GameMomentCard item={item} /></li>)}</ol>);

describe("GameMomentCard", () => {
  it("shows a multiplayer win with who it was over", () => {
    cards([{ ...base, game: "higher_or_lower", rawScore: 8, matchId: "m1", opponents: ["Ben"], opponentYou: true, opponentCount: 3 }]);
    expect(screen.getByText("Won Higher or Lower")).toBeInTheDocument();
    expect(screen.getByText(/Beat you, Ben and 1 other · Score 8/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Play" })).toHaveAttribute("href", "/party");
  });

  it("shows a new solo best as the number, with the friends rank and a way to beat it", () => {
    cards([
      { ...base, type: "high_score", game: "higher_or_lower", rawScore: 14, friendRank: 2, friendCount: 5 },
      { ...base, type: "high_score", game: "qb_season_builder", mode: "hidden", rawScore: 88.5, occurredAt: "2026-10-08T09:00:00Z" },
    ]);
    expect(screen.getByText("14")).toBeInTheDocument();
    expect(screen.getAllByText(/^in\s/)).toHaveLength(2);
    expect(screen.getByText(/#2 of 5 among you and your friends/)).toBeInTheDocument();
    expect(screen.getByText("88.5")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "QB Season Builder" })).toHaveAttribute("href", "/solo/qb-season-builder/leaderboard?scope=friends&mode=hidden");
    expect(screen.getAllByRole("link", { name: "Beat it" })[0]).toHaveAttribute("href", "/solo");
  });

  it("folds one friend's wins on the same day into a single card", () => {
    cards([
      { ...base, game: "higher_or_lower", matchId: "m1" },
      { ...base, game: "qb_season_builder", matchId: "m2", occurredAt: "2026-10-08T08:00:00Z" },
    ]);
    expect(screen.getByText("2 wins")).toBeInTheDocument();
    expect(screen.getByText("Won 2 games: Higher or Lower, QB Season Builder")).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(1);
  });
});

describe("groupActivity", () => {
  const win = (id: string, actorId: string, at: string): ActivityEvent => ({ ...base, matchId: id, actorId, occurredAt: at });

  it("merges back-to-back wins by the same friend on one day, and nothing else", () => {
    const items = groupActivity([
      win("m1", "a1", "2026-10-08T10:00:00Z"),
      win("m2", "a1", "2026-10-08T09:00:00Z"),
      win("m3", "a2", "2026-10-08T08:00:00Z"),
      win("m4", "a1", "2026-10-07T08:00:00Z"),
    ]);
    expect(items.map((item) => [item.event.matchId, item.more.length])).toEqual([["m1", 1], ["m3", 0], ["m4", 0]]);
  });
});

describe("beatLine", () => {
  it("names the caller and friends and counts everyone else", () => {
    expect(beatLine([], true, 1)).toBe("you");
    expect(beatLine(["Ava"], true, 2)).toBe("you and Ava");
    expect(beatLine(["Ava", "Ben"], false, 4)).toBe("Ava, Ben and 2 others");
    expect(beatLine([], false, 2)).toBe("2 players");
    expect(beatLine([], false, 0)).toBeNull();
  });
});
