import { describe, expect, it } from "vitest";

import {
  badgeLabel,
  inboxDetail,
  inboxHasActions,
  inboxHref,
  inboxTitle,
  toInboxItem,
  type InboxItem,
} from "./inbox";

function item(overrides: Partial<InboxItem>): InboxItem {
  return {
    key: "n:1",
    kind: "friend_request",
    state: "pending",
    actorId: "u1",
    actorName: "Ava",
    actorUsername: "ava",
    actorAvatarUrl: null,
    refId: "ref-1",
    postId: null,
    selectedGame: null,
    memberCount: 1,
    replyCount: 1,
    isUnread: true,
    sortAt: "2026-11-08T10:00:00Z",
    ...overrides,
  };
}

describe("toInboxItem", () => {
  const row = {
    item_key: "n:1", kind: "take_reply", state: "active", actor_id: "u1", actor_username: "ava",
    actor_display_name: "Ava", actor_avatar_url: null, ref_id: "take-1", post_id: "post-1",
    selected_game: null, member_count: null, reply_count: 2, is_unread: true, sort_at: "2026-11-08T10:00:00Z",
  };

  it("reads a row", () => {
    expect(toInboxItem(row)).toMatchObject({ kind: "take_reply", state: "active", postId: "post-1", replyCount: 2, memberCount: 1 });
  });

  it("drops a kind or state this build does not know, so a newer server can add items", () => {
    expect(toInboxItem({ ...row, kind: "badge_earned" })).toBeNull();
    expect(toInboxItem({ ...row, state: "snoozed" })).toBeNull();
  });
});

describe("copy", () => {
  it("words each item by kind and state", () => {
    expect(inboxTitle(item({}))).toBe("Ava sent you a friend request");
    expect(inboxTitle(item({ state: "accepted" }))).toBe("You and Ava are now friends");
    expect(inboxTitle(item({ kind: "take_reply", state: "active" }))).toBe("Ava replied to your take");
    expect(inboxTitle(item({ kind: "take_reply", state: "active", replyCount: 3 }))).toBe("3 new replies to your take");
    expect(inboxTitle(item({ kind: "room_invite" }))).toBe("Ava invited you to a room");
    expect(inboxTitle(item({ kind: "room_invite", state: "expired" }))).toBe("Ava's room invite expired");
    expect(inboxTitle(item({ kind: "room_invite", state: "accepted" }))).toBe("You joined Ava's room");
    expect(inboxTitle(item({ kind: "room_invite", state: "declined" }))).toBe("You declined Ava's invite");
  });

  it("describes a live invite's room, and nothing for the rest", () => {
    expect(inboxDetail(item({ kind: "room_invite", selectedGame: "higher_or_lower", memberCount: 2 }))).toBe("Higher or Lower · 2 of 4 players");
    expect(inboxDetail(item({ kind: "room_invite", state: "expired" }))).toBeNull();
    expect(inboxDetail(item({}))).toBeNull();
  });
});

describe("routing and actions", () => {
  it("sends a request to the profile and a reply to the take", () => {
    expect(inboxHref(item({}))).toBe("/u/ava");
    expect(inboxHref(item({ kind: "take_reply", state: "active", postId: "post-1", refId: "take-1" }))).toBe("/prompts/post-1/takes/take-1");
    expect(inboxHref(item({ kind: "room_invite" }))).toBeNull();
  });

  it("offers actions only while a request or invite can still be answered", () => {
    expect(inboxHasActions(item({}))).toBe(true);
    expect(inboxHasActions(item({ state: "accepted" }))).toBe(false);
    expect(inboxHasActions(item({ kind: "room_invite" }))).toBe(true);
    expect(inboxHasActions(item({ kind: "room_invite", state: "expired" }))).toBe(false);
    expect(inboxHasActions(item({ kind: "take_reply", state: "active" }))).toBe(false);
  });
});

describe("badgeLabel", () => {
  it("is empty for zero, the count up to nine, then 9+", () => {
    expect([0, 1, 9, 10].map(badgeLabel)).toEqual([null, "1", "9", "9+"]);
  });
});
