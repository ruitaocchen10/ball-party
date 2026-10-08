/** What `send_friend_request` / `redeem_friend_code` return. Anything else reads as `unavailable`. */
export type SendResult = "requested" | "accepted" | "already_requested" | "already_friends" | "unavailable";

const SEND_RESULTS: readonly SendResult[] = ["requested", "accepted", "already_requested", "already_friends", "unavailable"];

export function parseSendResult(value: unknown): SendResult {
  return SEND_RESULTS.find((result) => result === value) ?? "unavailable";
}

/**
 * `unavailable` covers "no such player", "they blocked you" and "you blocked
 * them" alike, so its copy must not hint at which one it is.
 */
export const SEND_RESULT_COPY: Record<SendResult, string> = {
  requested: "Friend request sent.",
  accepted: "You're now friends.",
  already_requested: "You've already sent a request.",
  already_friends: "You're already friends.",
  unavailable: "Couldn't add that player.",
};

/** The viewer's relationship to someone, as the RPCs report it. */
export type Relationship = "self" | "none" | "friends" | "outgoing" | "incoming" | "blocked";

export function parseRelationship(value: unknown): Relationship {
  const known: readonly Relationship[] = ["self", "none", "friends", "outgoing", "incoming", "blocked"];
  return known.find((relationship) => relationship === value) ?? "none";
}

const FRIEND_MESSAGES: Record<string, string> = {
  guests_cannot_have_friends: "Friends need a real account.",
  not_authenticated: "Sign in first.",
  rate_limited: "Too many tries. Wait a bit and try again.",
};

export function friendErrorMessage(message: string | undefined): string {
  return (message && FRIEND_MESSAGES[message]) || "Something went wrong. Try again.";
}

/** The shareable link for an invite code. The server owns the code; clients build the link. */
export function friendInvitePath(code: string): string {
  return `/friends/invite/${encodeURIComponent(code)}`;
}

// Plain module (no "use client") so server pages can call friendsDataFromRows.
export type PlayerSummary = {
  profileId: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
};

export type FriendsData = {
  friends: PlayerSummary[];
  incoming: PlayerSummary[];
  outgoing: PlayerSummary[];
  blocked: PlayerSummary[];
};

type Row = { profile_id: string; username: string | null; display_name: string; avatar_url: string | null };

function toPlayer(row: Row): PlayerSummary {
  return { profileId: row.profile_id, username: row.username, displayName: row.display_name, avatarUrl: row.avatar_url };
}

/** The shape the page hands over, built from the three list RPCs. */
export function friendsDataFromRows(
  friends: Row[],
  requests: (Row & { direction: string })[],
  blocked: Row[],
): FriendsData {
  return {
    friends: friends.map(toPlayer),
    incoming: requests.filter((row) => row.direction === "incoming").map(toPlayer),
    outgoing: requests.filter((row) => row.direction === "outgoing").map(toPlayer),
    blocked: blocked.map(toPlayer),
  };
}
