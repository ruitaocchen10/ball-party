// What a push says. Alerts use fixed, generic copy: nothing private (names,
// take text) is put on a lock screen, and the app fetches the details itself
// from the inbox when it is opened. The payload carries only the kind and ids.

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
  devices: Device[];
}

const ALERTS: Record<PushKind, { title: string; body: string }> = {
  friend_request: { title: "New friend request", body: "Open Ball Party to respond." },
  take_reply: { title: "New reply to your take", body: "Open Ball Party to read it." },
  room_invite: { title: "Room invite", body: "A friend invited you to a room." },
  new_prompt: { title: "New prompt", body: "A new prompt just dropped." },
};

/** The JSON body APNs delivers. The custom keys are the app's `PushPayload` contract. */
export function buildPayload(job: PushJob): Record<string, unknown> {
  return {
    aps: {
      alert: ALERTS[job.kind],
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
