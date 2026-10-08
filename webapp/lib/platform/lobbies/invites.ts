import { LOBBY_MESSAGES } from "@/lib/platform/lobbies/messages";

/** What `invite_friend_to_room` returns. Anything else is treated as `unavailable`. */
export type InviteResult = "invited" | "already_invited" | "already_in_room" | "room_full" | "unavailable";

const INVITE_RESULTS: readonly InviteResult[] = ["invited", "already_invited", "already_in_room", "room_full", "unavailable"];

export function parseInviteResult(value: unknown): InviteResult {
  return INVITE_RESULTS.find((result) => result === value) ?? "unavailable";
}

export const INVITE_RESULT_COPY: Record<InviteResult, { label: string; detail: string }> = {
  invited: { label: "Invited", detail: "Invite sent. They'll see it on their Party page." },
  already_invited: { label: "Already invited", detail: "They already have an invite to this room." },
  already_in_room: { label: "In the room", detail: "They're already in this room." },
  room_full: { label: "Room full", detail: "This room has no open spots." },
  unavailable: { label: "Unavailable", detail: "That friend can't be invited right now." },
};

/** Results after which asking again would only repeat the answer. */
export function isInviteSettled(result: InviteResult): boolean {
  return result !== "unavailable";
}

const INVITE_MESSAGES: Record<string, string> = {
  ...LOBBY_MESSAGES,
  not_a_room_member: "Only people in the room can invite friends.",
  invite_not_found: "That invite is no longer available.",
  guests_cannot_have_friends: "Friends need a real account.",
  rate_limited: "Too many invites. Try again in a bit.",
};

export function inviteErrorMessage(message: string): string {
  return INVITE_MESSAGES[message] ?? "Something went wrong. Try again.";
}

/** "Higher or Lower room · 2 of 4 players", or just the headcount before a game is picked. */
export function inviteRoomSummary(gameLabel: string | null, memberCount: number): string {
  const players = `${memberCount} of 4 players`;
  return gameLabel ? `${gameLabel} · ${players}` : players;
}
