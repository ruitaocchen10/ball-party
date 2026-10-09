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

/** A row of `friend_activity`, camel-cased for the UI. */
export type ActivityEvent = {
  type: "pick_made" | "pick_result" | "match_result";
  occurredAt: string;
  actorId: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
  postId: string | null;
  postCaption: string | null;
  points: number | null;
  matchId: string | null;
  game: string | null;
  placement: number | null;
  rawScore: number | null;
  runMode: string | null;
};

export const ACTIVITY_PAGE_SIZE = 30;

type ActivityRow = {
  event_type: string;
  occurred_at: string;
  actor_id: string;
  username: string | null;
  display_name: string;
  avatar_url: string | null;
  post_id: string | null;
  post_caption: string | null;
  points: number | null;
  match_id: string | null;
  game: string | null;
  placement: number | null;
  raw_score: number | null;
  run_mode: string | null;
};

export function activityEvents(rows: ActivityRow[]): ActivityEvent[] {
  return rows.flatMap((row) => {
    if (row.event_type !== "pick_made" && row.event_type !== "pick_result" && row.event_type !== "match_result") return [];
    return [{
      type: row.event_type,
      occurredAt: row.occurred_at,
      actorId: row.actor_id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      postId: row.post_id,
      postCaption: row.post_caption,
      points: row.points,
      matchId: row.match_id,
      game: row.game,
      placement: row.placement,
      rawScore: row.raw_score,
      runMode: row.run_mode,
    }];
  });
}

export function ordinalPlace(value: number): string {
  const remainder = value % 100;
  if (remainder >= 11 && remainder <= 13) return `${value}th`;
  return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`;
}

/** "5m ago", "3h ago", "2d ago"; older than a month falls back to the date. */
export function timeAgo(iso: string, now: Date = new Date()): string {
  const seconds = Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / 1000));
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 31) return `${days}d ago`;
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(iso));
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
