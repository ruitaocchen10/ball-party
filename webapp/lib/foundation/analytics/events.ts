/**
 * Every analytics event the web client sends, with its properties. The names
 * and property keys mirror docs/analytics/events.json, which iOS is held to as
 * well; events.test.ts fails if this file and that one drift.
 */
export type AuthMethod = "email" | "google" | "apple";

export type AnalyticsEvents = {
  signed_up: { method: AuthMethod };
  signed_in: { method: AuthMethod };
  party_created: Record<string, never>;
  party_joined: Record<string, never>;
  game_started: { game: string; solo: boolean };
  prompt_answered: { post_id: string };
  take_posted: { post_id: string; is_reply: boolean };
  invite_link_shared: { kind: "friend" | "room" };
  invite_accepted: { kind: "friend"; result: string };
};

export type AnalyticsEventName = keyof AnalyticsEvents;

/** Events web sends. `push_enabled` is iOS-only (web has no push), so it is not here. */
export const WEB_EVENT_NAMES: readonly AnalyticsEventName[] = [
  "signed_up",
  "signed_in",
  "party_created",
  "party_joined",
  "game_started",
  "prompt_answered",
  "take_posted",
  "invite_link_shared",
  "invite_accepted",
];
