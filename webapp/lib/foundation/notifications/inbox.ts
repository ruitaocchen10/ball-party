import { MATCH_GAME_NAMES, type MatchGame } from "@/lib/platform/orchestration/catalog";
import { inviteRoomSummary } from "@/lib/platform/lobbies/invites";

/**
 * The notification inbox as `list_inbox` reports it (migration 0204). The
 * server decides which items exist and what state each is in; this file only
 * turns a row into the words and the destination the bell shows. The iOS app
 * carries the same copy (`InboxItem.swift`), so change them together.
 */

export type InboxKind = "friend_request" | "take_reply" | "room_invite";
export type InboxState = "pending" | "accepted" | "declined" | "expired" | "active";

export type InboxItem = {
  /** `n:<uuid>` for a stored notification, `i:<uuid>` for a room invite. */
  key: string;
  kind: InboxKind;
  state: InboxState;
  actorId: string;
  actorName: string;
  actorUsername: string | null;
  actorAvatarUrl: string | null;
  /** friend_request: the friendship. take_reply: the take. room_invite: the invite. */
  refId: string;
  postId: string | null;
  selectedGame: string | null;
  memberCount: number;
  replyCount: number;
  isUnread: boolean;
  sortAt: string;
};

type InboxRow = {
  item_key: string;
  kind: string;
  state: string;
  actor_id: string;
  actor_username: string | null;
  actor_display_name: string | null;
  actor_avatar_url: string | null;
  ref_id: string;
  post_id: string | null;
  selected_game: string | null;
  member_count: number | null;
  reply_count: number;
  is_unread: boolean;
  sort_at: string;
};

const KINDS: readonly InboxKind[] = ["friend_request", "take_reply", "room_invite"];
const STATES: readonly InboxState[] = ["pending", "accepted", "declined", "expired", "active"];

/** A row of `list_inbox`. A kind or state this build doesn't know is dropped, so an older client ignores a newer server's items rather than guessing at them. */
export function toInboxItem(row: InboxRow): InboxItem | null {
  const kind = KINDS.find((k) => k === row.kind);
  const state = STATES.find((s) => s === row.state);
  if (!kind || !state) return null;
  return {
    key: row.item_key,
    kind,
    state,
    actorId: row.actor_id,
    actorName: row.actor_display_name ?? row.actor_username ?? "A player",
    actorUsername: row.actor_username,
    actorAvatarUrl: row.actor_avatar_url,
    refId: row.ref_id,
    postId: row.post_id,
    selectedGame: row.selected_game,
    memberCount: row.member_count ?? 1,
    replyCount: row.reply_count,
    isUnread: row.is_unread,
    sortAt: row.sort_at,
  };
}

export function toInboxItems(rows: readonly InboxRow[]): InboxItem[] {
  return rows.flatMap((row) => toInboxItem(row) ?? []);
}

/** The main line of an item. */
export function inboxTitle(item: InboxItem): string {
  const name = item.actorName;
  switch (item.kind) {
    case "friend_request":
      return item.state === "accepted" ? `You and ${name} are now friends` : `${name} sent you a friend request`;
    case "take_reply":
      return item.replyCount > 1 ? `${item.replyCount} new replies to your take` : `${name} replied to your take`;
    case "room_invite":
      switch (item.state) {
        case "accepted":
          return `You joined ${name}'s room`;
        case "declined":
          return `You declined ${name}'s invite`;
        case "expired":
          return `${name}'s room invite expired`;
        default:
          return `${name} invited you to a room`;
      }
  }
}

/** The line under the title, or null when there is nothing more to say. */
export function inboxDetail(item: InboxItem): string | null {
  if (item.kind === "take_reply" && item.replyCount > 1) return `Latest from ${item.actorName}`;
  if (item.kind === "room_invite" && item.state === "pending") {
    const game =
      item.selectedGame && item.selectedGame in MATCH_GAME_NAMES ? MATCH_GAME_NAMES[item.selectedGame as MatchGame] : null;
    return inviteRoomSummary(game, item.memberCount);
  }
  return null;
}

/** Where tapping an item goes. Room invites have no page of their own: they act in place. */
export function inboxHref(item: InboxItem): string | null {
  switch (item.kind) {
    case "friend_request":
      return item.actorUsername ? `/u/${encodeURIComponent(item.actorUsername)}` : null;
    case "take_reply":
      return item.postId ? `/prompts/${item.postId}/takes/${item.refId}` : null;
    case "room_invite":
      return null;
  }
}

/** Whether an item offers Accept / Decline (Join / Decline for a room). */
export function inboxHasActions(item: InboxItem): boolean {
  return (item.kind === "friend_request" || item.kind === "room_invite") && item.state === "pending";
}

/** The bell's badge text: nothing for zero, the count up to nine, then 9+. */
export function badgeLabel(count: number): string | null {
  if (count <= 0) return null;
  return count > 9 ? "9+" : String(count);
}
