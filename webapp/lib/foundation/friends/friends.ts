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

/** A game moment from `friend_activity` (a multiplayer win or a new solo best), camel-cased for the UI. */
export type ActivityEvent = {
  type: "win" | "high_score";
  occurredAt: string;
  actorId: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
  matchId: string | null;
  game: string | null;
  placement: number | null;
  /** A win's score, or a high score's new best. */
  rawScore: number | null;
  runMode: string | null;
  /** The QB Season Builder board a high score is on (visible or hidden). */
  mode: string | null;
  /** A win: the beaten players who are the caller's friends. */
  opponents: string[];
  /** A win: the caller was one of the players beaten. */
  opponentYou: boolean;
  /** A win: everyone the winner beat. */
  opponentCount: number;
  /** A high score: where the new best sits among the caller and their friends. */
  friendRank: number | null;
  friendCount: number | null;
};

export const ACTIVITY_PAGE_SIZE = 30;

type ActivityRow = {
  event_type: string;
  occurred_at: string;
  actor_id: string;
  username: string | null;
  display_name: string;
  avatar_url: string | null;
  match_id: string | null;
  game: string | null;
  placement: number | null;
  raw_score: number | null;
  run_mode: string | null;
  mode: string | null;
  opponents: string[] | null;
  opponent_you: boolean | null;
  opponent_count: number | null;
  friend_rank: number | null;
  friend_count: number | null;
};

const ACTIVITY_TYPES = ["win", "high_score"] as const;

export function activityEvents(rows: ActivityRow[]): ActivityEvent[] {
  return rows.flatMap((row) => {
    const type = ACTIVITY_TYPES.find((known) => known === row.event_type);
    if (!type) return [];
    return [{
      type,
      occurredAt: row.occurred_at,
      actorId: row.actor_id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      matchId: row.match_id,
      game: row.game,
      placement: row.placement,
      rawScore: row.raw_score,
      runMode: row.run_mode,
      mode: row.mode,
      opponents: row.opponents ?? [],
      opponentYou: row.opponent_you ?? false,
      opponentCount: row.opponent_count ?? 0,
      friendRank: row.friend_rank,
      friendCount: row.friend_count,
    }];
  });
}

/** One feed entry. A friend's wins on the same day fold into one entry led by the newest; `more` holds the rest. */
export type ActivityItem = { event: ActivityEvent; more: ActivityEvent[] };

/** Folds back-to-back wins by the same friend on the same (UTC) day into one entry, so a busy player doesn't fill the feed. */
export function groupActivity(events: ActivityEvent[]): ActivityItem[] {
  const items: ActivityItem[] = [];
  for (const event of events) {
    const last = items[items.length - 1];
    if (
      event.type === "win" &&
      last?.event.type === "win" &&
      last.event.actorId === event.actorId &&
      last.event.occurredAt.slice(0, 10) === event.occurredAt.slice(0, 10)
    ) {
      last.more.push(event);
    } else {
      items.push({ event, more: [] });
    }
  }
  return items;
}

/** A friend who answered a prompt: the fact only, never the pick. */
export type FriendAnswerer = {
  actorId: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
  answeredAt: string;
};

type AnswererRow = { post_id: string; actor_id: string; username: string | null; display_name: string; avatar_url: string | null; answered_at: string };

/** `friends_who_answered` rows grouped by prompt, newest answer first. */
export function answerersByPost(rows: AnswererRow[]): Record<string, FriendAnswerer[]> {
  const byPost: Record<string, FriendAnswerer[]> = {};
  for (const row of rows) {
    const list = byPost[row.post_id] ?? [];
    list.push({ actorId: row.actor_id, username: row.username, displayName: row.display_name, avatarUrl: row.avatar_url, answeredAt: row.answered_at });
    byPost[row.post_id] = list;
  }
  for (const list of Object.values(byPost)) list.sort((a, b) => Date.parse(b.answeredAt) - Date.parse(a.answeredAt));
  return byPost;
}

/**
 * Who answered, friends first. With the prompt's total: "Sam and 5 others have answered",
 * "Sam, Jo and 4 others have answered", "Sam and Jo have answered". Without it (the
 * headcount is hidden): "Sam answered", "Sam & Jo answered", "Sam, Jo & 2 other friends answered".
 */
export function friendsAnsweredLine(answerers: FriendAnswerer[], total?: number): string | null {
  const names = answerers.map((a) => a.displayName);
  if (names.length === 0) return null;
  if (total !== undefined) {
    const shown = names.slice(0, 2);
    const rest = Math.max(0, total - shown.length);
    const list = shown.length === 2 && rest === 0 ? `${shown[0]} and ${shown[1]}` : shown.join(", ");
    if (rest > 0) return `${list} and ${rest} ${rest === 1 ? "other has" : "others have"} answered`;
    return `${list} ${shown.length === 1 ? "has" : "have"} answered`;
  }
  if (names.length === 1) return `${names[0]} answered`;
  if (names.length === 2) return `${names[0]} & ${names[1]} answered`;
  const others = names.length - 2;
  return `${names[0]}, ${names[1]} & ${others} other ${others === 1 ? "friend" : "friends"} answered`;
}

export type HomeFilter = "all" | "prompts" | "friends" | "lists";

export function parseHomeFilter(value: string | undefined, canUseFriends: boolean): HomeFilter {
  if (!canUseFriends) return "all";
  return value === "prompts" || value === "friends" || value === "lists" ? value : "all";
}

export type HomeFeedItem<P extends { id: string; createdAt: string }> =
  | { kind: "prompt"; at: string; post: P; answerers: FriendAnswerer[] }
  | { kind: "moment"; at: string; item: ActivityItem };

/**
 * One feed from prompts and game moments, newest first. A prompt is dated by
 * when it was posted (All) or by the newest friend answer (Friends, which only
 * keeps prompts a friend answered). Game moments come from the paged
 * `friend_activity`, so the feed pages with them: a full activity page bounds the
 * window at its oldest event, and `olderBefore` is that bound for the next page.
 * Prompts and moments older than `before` only; a short page means no more moments, so no bound.
 */
export function buildHomeFeed<P extends { id: string; createdAt: string }>({
  posts,
  answerers,
  moments,
  filter,
  before,
  pageFull,
}: {
  posts: P[];
  answerers: Record<string, FriendAnswerer[]>;
  moments: ActivityEvent[];
  filter: HomeFilter;
  before: string | null;
  pageFull: boolean;
}): { items: HomeFeedItem<P>[]; olderBefore: string | null } {
  // The Lists pill is only list updates, which the feed adds itself (lib/foundation/lists).
  if (filter === "lists") return { items: [], olderBefore: null };
  if (filter === "prompts") {
    return { items: posts.map((post) => ({ kind: "prompt", at: post.createdAt, post, answerers: [] })), olderBefore: null };
  }
  const prompts: HomeFeedItem<P>[] = posts.flatMap((post) => {
    const who = answerers[post.id] ?? [];
    if (filter === "friends" && who.length === 0) return [];
    return [{ kind: "prompt" as const, at: filter === "friends" ? who[0].answeredAt : post.createdAt, post, answerers: who }];
  });
  const games: HomeFeedItem<P>[] = groupActivity(moments).map((item) => ({ kind: "moment", at: item.event.occurredAt, item }));
  const floor = pageFull && moments.length > 0 ? moments[moments.length - 1].occurredAt : null;
  const items = [...prompts, ...games]
    .filter((entry) => (before === null || Date.parse(entry.at) < Date.parse(before)) && (floor === null || Date.parse(entry.at) >= Date.parse(floor)))
    .sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
  return { items, olderBefore: floor };
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
