import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { groupActivity, type ActivityEvent } from "@/lib/foundation/friends/friends";
import { ActivityFeed } from "./ActivityFeed";
import { beatLine } from "./GameMomentCard";

const base: ActivityEvent = {
  type: "pick_made",
  occurredAt: "2026-10-08T10:00:00Z",
  actorId: "a1",
  username: "ava",
  displayName: "Ava",
  avatarUrl: null,
  postId: "post-1",
  postCaption: "Week 5 picks",
  takeBody: null,
  commentId: null,
  replyCount: 0,
  response: null,
  points: null,
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

const feed = (events: ActivityEvent[], olderHref: string | null = null) =>
  render(<ActivityFeed events={events} posts={new Map()} hasFriends olderHref={olderHref} />);

describe("ActivityFeed", () => {
  it("shows a take as a card with its prompt, and only that an open pick was made", () => {
    feed([
      base,
      { ...base, type: "take", points: 12, takeBody: "Chiefs in a walk", commentId: "c1", replyCount: 2, occurredAt: "2026-10-08T09:00:00Z" },
    ]);
    expect(screen.getByText(/Their picks show when it locks/)).toBeInTheDocument();
    expect(screen.getByText("Chiefs in a walk")).toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Week 5 picks" }).every((link) => link.getAttribute("href") === "/prompts/post-1")).toBe(true);
    expect(screen.getByRole("link", { name: /Comment on Ava's take/ })).toHaveAttribute("href", "/prompts/post-1/takes/c1");
    expect(screen.getByText("+12")).toBeInTheDocument();
  });

  it("links a take with no posted comment to the prompt's discussion", () => {
    feed([{ ...base, type: "take", commentId: null, takeBody: null }]);
    expect(screen.getByRole("link", { name: /Comment on Ava's take/ })).toHaveAttribute("href", "/prompts/post-1");
  });

  it("shows the author's @username under their name on a take card, in place of a rank label", () => {
    feed([{ ...base, type: "take", takeBody: "Chiefs in a walk", commentId: "c1" }]);
    expect(screen.getByText("@ava")).toBeInTheDocument();
    expect(screen.queryByText("Rookie")).not.toBeInTheDocument();
  });

  it("shows a multiplayer win with who it was over", () => {
    feed([{ ...base, type: "win", game: "higher_or_lower", rawScore: 8, postId: null, matchId: "m1", opponents: ["Ben"], opponentYou: true, opponentCount: 3 }]);
    expect(screen.getByText("Won Higher or Lower")).toBeInTheDocument();
    expect(screen.getByText(/Beat you, Ben and 1 other · Score 8/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Play" })).toHaveAttribute("href", "/party");
  });

  it("shows a new solo best as the number, with the friends rank and a way to beat it", () => {
    feed([
      { ...base, type: "high_score", game: "higher_or_lower", rawScore: 14, postId: null, friendRank: 2, friendCount: 5 },
      { ...base, type: "high_score", game: "qb_season_builder", mode: "hidden", rawScore: 88.5, postId: null, occurredAt: "2026-10-08T09:00:00Z" },
    ]);
    expect(screen.getByText("14")).toBeInTheDocument();
    expect(screen.getAllByText(/^in\s/)).toHaveLength(2);
    expect(screen.getByText(/#2 of 5 among you and your friends/)).toBeInTheDocument();
    expect(screen.getByText("88.5")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "QB Season Builder" })).toHaveAttribute("href", "/solo/qb-season-builder/leaderboard?scope=friends&mode=hidden");
    expect(screen.getAllByRole("link", { name: "Beat it" })[0]).toHaveAttribute("href", "/solo");
  });

  it("folds one friend's wins on the same day into a single card", () => {
    feed([
      { ...base, type: "win", game: "higher_or_lower", postId: null, matchId: "m1" },
      { ...base, type: "win", game: "qb_season_builder", postId: null, matchId: "m2", occurredAt: "2026-10-08T08:00:00Z" },
    ]);
    expect(screen.getByText("2 wins")).toBeInTheDocument();
    expect(screen.getByText("Won 2 games: Higher or Lower, QB Season Builder")).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(1);
  });

  it("explains an empty feed with no friends, and with friends", () => {
    const { rerender } = render(<ActivityFeed events={[]} posts={new Map()} hasFriends={false} olderHref={null} />);
    expect(screen.getByText("No friends yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Find friends" })).toHaveAttribute("href", "/profile?tab=friends");

    rerender(<ActivityFeed events={[]} posts={new Map()} hasFriends olderHref={null} />);
    expect(screen.getByText("Nothing yet")).toBeInTheDocument();
  });

  it("links to older events only when there are some", () => {
    const { unmount } = feed([base], "/?view=friends&before=2026-10-08T10%3A00%3A00Z");
    expect(screen.getByRole("link", { name: "Older" })).toHaveAttribute("href", "/?view=friends&before=2026-10-08T10%3A00%3A00Z");
    unmount();
    feed([base]);
    expect(screen.queryByRole("link", { name: "Older" })).not.toBeInTheDocument();
  });
});

describe("groupActivity", () => {
  const win = (id: string, actorId: string, at: string): ActivityEvent => ({ ...base, type: "win", matchId: id, actorId, occurredAt: at });

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
