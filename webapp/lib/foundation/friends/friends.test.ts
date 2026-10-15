import { describe, expect, it } from "vitest";

import {
  activityEvents,
  buildHomeFeed,
  friendsAnsweredLine,
  parseHomeFilter,
  type ActivityEvent,
  friendErrorMessage,
  friendInvitePath,
  ordinalPlace,
  timeAgo,
  parseRelationship,
  parseSendResult,
} from "./friends";

describe("friends helpers", () => {
  it("treats unknown send results as unavailable", () => {
    expect(parseSendResult("requested")).toBe("requested");
    expect(parseSendResult("blocked")).toBe("unavailable");
    expect(parseSendResult(null)).toBe("unavailable");
  });

  it("parses relationships defensively", () => {
    expect(parseRelationship("incoming")).toBe("incoming");
    expect(parseRelationship("weird")).toBe("none");
  });

  it("maps known errors and hides unknown ones", () => {
    expect(friendErrorMessage("guests_cannot_have_friends")).toBe("Friends need a real account.");
    expect(friendErrorMessage("pg exploded")).toBe("Something went wrong. Try again.");
  });

  it("builds the invite path", () => {
    expect(friendInvitePath("ABC123")).toBe("/friends/invite/ABC123");
  });

  it("formats places and relative times", () => {
    expect(ordinalPlace(1)).toBe("1st");
    expect(ordinalPlace(2)).toBe("2nd");
    expect(ordinalPlace(3)).toBe("3rd");
    expect(ordinalPlace(11)).toBe("11th");
    const now = new Date("2026-10-08T12:00:00Z");
    expect(timeAgo("2026-10-08T11:59:30Z", now)).toBe("just now");
    expect(timeAgo("2026-10-08T11:55:00Z", now)).toBe("5m ago");
    expect(timeAgo("2026-10-08T09:00:00Z", now)).toBe("3h ago");
    expect(timeAgo("2026-10-06T12:00:00Z", now)).toBe("2d ago");
  });

  it("keeps only game moments, dropping prompt answers and unknown types", () => {
    const base = {
      occurred_at: "2026-10-08T00:00:00Z", actor_id: "a", username: "ava", display_name: "Ava", avatar_url: null,
      mode: null, opponents: null, opponent_you: null, opponent_count: null, friend_rank: null, friend_count: null, match_id: null, game: null, placement: null, raw_score: null, run_mode: null,
    };
    const events = activityEvents([{ ...base, event_type: "win" }, { ...base, event_type: "take" }, { ...base, event_type: "mystery" }]);
    expect(events.map((event) => event.type)).toEqual(["win"]);
  });
});

describe("home feed", () => {
  const post = (id: string, createdAt: string) => ({ id, createdAt });
  const moment = (id: string, at: string): ActivityEvent => ({
    type: "win", occurredAt: at, actorId: "a1", username: "ava", displayName: "Ava", avatarUrl: null, matchId: id, game: "higher_or_lower",
    placement: 1, rawScore: 5, runMode: "arcade", mode: null, opponents: [], opponentYou: false, opponentCount: 1, friendRank: null, friendCount: null,
  });
  const answerer = (id: string, name: string, at: string) => ({ actorId: id, username: id, displayName: name, avatarUrl: null, answeredAt: at });

  it("interleaves prompts and game moments by time", () => {
    const { items } = buildHomeFeed({
      posts: [post("p1", "2026-10-08T12:00:00Z"), post("p2", "2026-10-06T12:00:00Z")],
      answerers: {}, moments: [moment("m1", "2026-10-07T12:00:00Z")], filter: "all", before: null, pageFull: false,
    });
    expect(items.map((item) => (item.kind === "prompt" ? item.post.id : item.item.event.matchId))).toEqual(["p1", "m1", "p2"]);
  });

  it("Prompts shows every prompt and no game moments", () => {
    const { items, olderBefore } = buildHomeFeed({ posts: [post("p1", "2026-10-08T12:00:00Z")], answerers: {}, moments: [moment("m1", "2026-10-09T12:00:00Z")], filter: "prompts", before: null, pageFull: true });
    expect(items).toHaveLength(1);
    expect(olderBefore).toBeNull();
  });

  it("Friends keeps only prompts a friend answered, dated by the newest answer", () => {
    const { items } = buildHomeFeed({
      posts: [post("p1", "2026-10-01T12:00:00Z"), post("p2", "2026-10-02T12:00:00Z")],
      answerers: { p1: [answerer("a1", "Ava", "2026-10-09T12:00:00Z")] },
      moments: [moment("m1", "2026-10-08T12:00:00Z")], filter: "friends", before: null, pageFull: false,
    });
    expect(items.map((item) => (item.kind === "prompt" ? item.post.id : item.item.event.matchId))).toEqual(["p1", "m1"]);
  });

  it("a full page of moments bounds the window, and the next page picks up below it", () => {
    const posts = [post("new", "2026-10-09T00:00:00Z"), post("old", "2026-10-01T00:00:00Z")];
    const moments = [moment("m1", "2026-10-08T00:00:00Z"), moment("m2", "2026-10-05T00:00:00Z")];
    const first = buildHomeFeed({ posts, answerers: {}, moments, filter: "all", before: null, pageFull: true });
    expect(first.items.map((item) => item.at)).toEqual(["2026-10-09T00:00:00Z", "2026-10-08T00:00:00Z", "2026-10-05T00:00:00Z"]);
    expect(first.olderBefore).toBe("2026-10-05T00:00:00Z");
    const next = buildHomeFeed({ posts, answerers: {}, moments: [], filter: "all", before: first.olderBefore, pageFull: false });
    expect(next.items.map((item) => (item.kind === "prompt" ? item.post.id : ""))).toEqual(["old"]);
  });

  it("words who answered", () => {
    expect(friendsAnsweredLine([])).toBeNull();
    expect(friendsAnsweredLine([answerer("a", "Ava", "x")])).toBe("Ava answered");
    expect(friendsAnsweredLine([answerer("a", "Ava", "x"), answerer("b", "Ben", "x")])).toBe("Ava & Ben answered");
    expect(friendsAnsweredLine([answerer("a", "Ava", "x"), answerer("b", "Ben", "x"), answerer("c", "Cy", "x")])).toBe("Ava, Ben & 1 other friend answered");
  });

  it("folds the headcount into the line when it is known", () => {
    const a = answerer("a", "Ava", "x"), b = answerer("b", "Ben", "x"), c = answerer("c", "Cy", "x");
    expect(friendsAnsweredLine([a], 6)).toBe("Ava and 5 others have answered");
    expect(friendsAnsweredLine([a], 2)).toBe("Ava and 1 other has answered");
    expect(friendsAnsweredLine([a], 1)).toBe("Ava has answered");
    expect(friendsAnsweredLine([a, b], 2)).toBe("Ava and Ben have answered");
    expect(friendsAnsweredLine([a, b, c], 7)).toBe("Ava, Ben and 5 others have answered");
  });

  it("parses the filter, defaulting to All and ignoring Friends for guests", () => {
    expect(parseHomeFilter("friends", true)).toBe("friends");
    expect(parseHomeFilter("friends", false)).toBe("all");
    expect(parseHomeFilter("nope", true)).toBe("all");
    expect(parseHomeFilter("lists", true)).toBe("lists");
    expect(parseHomeFilter("lists", false)).toBe("all");
  });
});
