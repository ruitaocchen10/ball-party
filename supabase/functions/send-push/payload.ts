// What a push says. A lock screen shows the title on one line (about 35-45
// characters, then an ellipsis) and a few lines of body, so the title names the
// what and the body carries the detail, and every variable part is capped.
// Friend, reply and invite alerts name the person (never take text); the app
// fetches everything else from the inbox when it is opened. The payload keeps
// only the kind and ids beside the alert.

export type PushKind = "friend_request" | "take_reply" | "room_invite" | "new_prompt";
export type ApnsEnvironment = "sandbox" | "production";

export interface Device {
  token: string;
  environment: ApnsEnvironment;
}

/** One claimed outbox row, as `claim_push_batch` (migration 0206) returns it. */
export interface PushJob {
  id: number;
  kind: PushKind;
  /** The inbox item the alert is for ('n:<uuid>' / 'i:<uuid>'); null for a new prompt. */
  item_key: string | null;
  post_id: string | null;
  /** The recipient's unread inbox count. */
  badge: number;
  /** Facts for the alert copy from `push_info` (migration 0219); null when there are none. */
  info?: PushInfo | null;
  devices: Device[];
}

export interface PushInfo {
  /** Inbox kinds: the person behind the item. */
  actor_name?: string;
  /** take_reply: replies folded into the item. */
  reply_count?: number;
  /** new_prompt */
  template_kind?: string;
  caption?: string;
  lock_at?: string;
  week?: number;
  /** A game pick's matchup, kickoff and points. */
  away_team?: string;
  home_team?: string;
  kickoff?: string;
  primetime?: boolean;
  points?: number;
}

export interface Alert {
  title: string;
  body: string;
}

const NAME_MAX = 15;
const CAPTION_MAX = 90;

const ALERTS: Record<PushKind, Alert> = {
  friend_request: { title: "New friend request", body: "Open Ball Party to respond." },
  take_reply: { title: "New reply to your take", body: "Open Ball Party to read it." },
  room_invite: { title: "Room invite", body: "A friend invited you to a room." },
  new_prompt: { title: "New prompt", body: "A new prompt just dropped." },
};

/** Cuts to `max` characters with an ellipsis; usernames and captions are not ours to size. */
export function clip(text: string, max: number): string {
  const t = text.trim().replace(/\s+/g, " ");
  return t.length <= max ? t : `${t.slice(0, max - 1).trimEnd()}\u2026`;
}

const eastern = (iso: string, opts: Intl.DateTimeFormatOptions) =>
  new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", ...opts }).format(new Date(iso));

/** "Sun 8:20 PM ET". Prompt times are Eastern everywhere else in the product. */
function when(iso: string): string {
  return `${eastern(iso, { weekday: "short" })} ${eastern(iso, { hour: "numeric", minute: "2-digit" })} ET`;
}

function promptAlert(info: PushInfo): Alert {
  const week = info.week ? `Week ${info.week}` : null;
  const lock = info.lock_at ? when(info.lock_at) : null;

  switch (info.template_kind) {
    case "game_pick": {
      if (!info.away_team || !info.home_team) break;
      const stakes = info.points ? ` ${info.points} pts.` : "";
      const time = info.kickoff ? ` (${when(info.kickoff)})` : "";
      return {
        title: `${info.away_team} @ ${info.home_team}`,
        body: `Pick the winner before kickoff${time}.${stakes}`,
      };
    }
    case "weekly_picks":
      return {
        title: week ? `${week} picks are open` : "Weekly picks are open",
        body: lock ? `Lock in your picks before ${lock}.` : "Lock in your picks before kickoff.",
      };
    case "bold_predictions":
      return {
        title: "Bold Predictions are open",
        body: lock ? `Call your shots before ${lock}.` : "Call your shots before kickoff.",
      };
    case "weekly_awards":
      return {
        title: week ? `${week} awards` : "Weekly awards",
        body: lock ? `Cast your votes before ${lock}.` : "Cast your votes today.",
      };
    case "power_rankings":
      return {
        title: week ? `${week} power rankings` : "Power rankings",
        body: lock ? `Rank the league before ${lock}.` : "Rank the league before kickoff.",
      };
  }
  // A kind with no template of its own: the admin's caption is the line.
  return info.caption ? { title: "New prompt", body: clip(info.caption, CAPTION_MAX) } : ALERTS.new_prompt;
}

/** The alert for one push; fixed copy when the facts for a richer one are missing. */
export function buildAlert(job: PushJob): Alert {
  const info = job.info ?? {};
  const name = info.actor_name ? clip(info.actor_name, NAME_MAX) : null;

  switch (job.kind) {
    case "friend_request":
      return name ? { title: "New friend request", body: `${name} wants to be friends.` } : ALERTS.friend_request;
    case "take_reply": {
      if (!name) return ALERTS.take_reply;
      const count = info.reply_count ?? 1;
      return count > 1
        ? { title: "New replies to your take", body: `${count} new replies, the latest from ${name}.` }
        : { title: "New reply to your take", body: `${name} replied to your take.` };
    }
    case "room_invite":
      return name ? { title: "Room invite", body: `${name} invited you to a room.` } : ALERTS.room_invite;
    case "new_prompt":
      return info.template_kind ? promptAlert(info) : ALERTS.new_prompt;
  }
}

/** The JSON body APNs delivers. The custom keys are the app's `PushPayload` contract. */
export function buildPayload(job: PushJob): Record<string, unknown> {
  return {
    aps: {
      alert: buildAlert(job),
      badge: job.badge,
      sound: "default",
      "thread-id": job.kind,
    },
    kind: job.kind,
    ...(job.item_key ? { item_key: job.item_key } : {}),
    ...(job.post_id ? { post_id: job.post_id } : {}),
  };
}

/**
 * Lets APNs replace an alert still on the lock screen rather than stack a
 * second one for the same thing.
 */
export function collapseId(job: PushJob): string | null {
  if (job.item_key) return job.item_key;
  if (job.post_id) return `prompt:${job.post_id}`;
  return null;
}
