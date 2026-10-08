import { describe, expect, it } from "vitest";

import {
  activityEvents,
  friendErrorMessage,
  friendInvitePath,
  ordinalPlace,
  parseFriendsTab,
  parseRelationship,
  parseSendResult,
  timeAgo,
} from "./friends";

describe("friends helpers", () => {
  it("treats unknown send results as unavailable", () => {
    expect(parseSendResult("requested")).toBe("requested");
    expect(parseSendResult("blocked")).toBe("unavailable");
    expect(parseSendResult(null)).toBe("unavailable");
  });

  it("parses relationships and tabs defensively", () => {
    expect(parseRelationship("incoming")).toBe("incoming");
    expect(parseRelationship("weird")).toBe("none");
    expect(parseFriendsTab("activity")).toBe("activity");
    expect(parseFriendsTab(["activity"])).toBe("activity");
    expect(parseFriendsTab("nope")).toBe("friends");
    expect(parseFriendsTab(undefined)).toBe("friends");
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

  it("drops activity rows of an unknown type", () => {
    const base = {
      occurred_at: "2026-10-08T00:00:00Z", actor_id: "a", username: "ava", display_name: "Ava", avatar_url: null,
      post_id: null, post_caption: null, points: null, match_id: null, game: null, placement: null, raw_score: null, run_mode: null,
    };
    const events = activityEvents([{ ...base, event_type: "pick_made" }, { ...base, event_type: "mystery" }]);
    expect(events.map((event) => event.type)).toEqual(["pick_made"]);
  });
});
