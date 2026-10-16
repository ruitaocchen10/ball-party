import type { SupabaseClient } from "@supabase/supabase-js";

import { buildCreatePostArgs, type CreatePostParams } from "@/lib/foundation/content/prompts/client";
import { promptErrorMessage } from "@/lib/foundation/content/prompts/messages";
import type { Database } from "@/lib/supabase/database.types";

/**
 * The admin prompt calendar (BPP-15, migration 0215). Slots live in a planning
 * table the database owns; this file only reads them through the
 * prompts.schedule_* RPCs and carries the labels the calendar and queue share.
 * Nothing here decides what is allowed: the RPCs do.
 */

/** The five lanes, in the order the calendar shows them. */
export const SLOT_KINDS = ["game_pick", "weekly_picks", "weekly_awards", "bold_predictions", "power_rankings"] as const;
export type SlotKind = (typeof SLOT_KINDS)[number];

export const SLOT_KIND_LABELS: Record<SlotKind, string> = {
  game_pick: "Game picks",
  weekly_picks: "Weekly picks",
  weekly_awards: "Weekly awards",
  bold_predictions: "Bold predictions",
  power_rankings: "Power rankings",
};

/** Stored states plus what a published slot's post has since become. */
export type SlotDisplayState = "empty" | "draft" | "ready" | "live" | "locked" | "resolved" | "void" | "removed";

export const SLOT_STATE_LABELS: Record<SlotDisplayState, string> = {
  empty: "Empty",
  draft: "Draft",
  ready: "Ready",
  live: "Live",
  locked: "Locked",
  resolved: "Resolved",
  void: "Void",
  removed: "Removed",
};

/** A row of prompts_private.schedule_slot_view, as prompts.schedule_list returns it. */
export type ScheduleSlot = {
  id: string;
  season: number;
  week: number;
  kind: SlotKind;
  game_id: string | null;
  state: "empty" | "draft" | "ready" | "published";
  display_state: SlotDisplayState;
  opens_at: string | null;
  lock_at: string | null;
  post_id: string | null;
  publish_error: string | null;
  has_draft: boolean;
  caption: string | null;
  missing: string[];
  due_at: string | null;
  needs_attention: boolean;
  attention: string | null;
};

/** One slot with its saved draft, from prompts.schedule_get. */
export type ScheduleSlotDetail = ScheduleSlot & {
  payload: { post?: Record<string, unknown>; composer?: Record<string, unknown> } | null;
};

type Client = SupabaseClient<Database>;

/** Slots whose day (open time, or lock time until one is set) falls in [from, to). */
export async function fetchScheduleRange(supabase: Client, from: Date, to: Date): Promise<ScheduleSlot[]> {
  const { data, error } = await supabase
    .schema("prompts")
    .rpc("schedule_range", { p_from: from.toISOString(), p_to: to.toISOString() });
  if (error) throw new Error(error.message);
  return (data ?? []) as unknown as ScheduleSlot[];
}

export async function fetchScheduleQueue(supabase: Client): Promise<ScheduleSlot[]> {
  const { data, error } = await supabase.schema("prompts").rpc("schedule_queue");
  if (error) throw new Error(error.message);
  return (data ?? []) as unknown as ScheduleSlot[];
}

export async function fetchScheduleSlot(supabase: Client, id: string): Promise<ScheduleSlotDetail | null> {
  const { data, error } = await supabase.schema("prompts").rpc("schedule_get", { p_slot: id });
  if (error) return null;
  return data as unknown as ScheduleSlotDetail;
}

/** Adds the slots for the coming weeks that don't exist yet; safe to run any time. */
export async function prefillSchedule(supabase: Client): Promise<void> {
  await supabase.schema("prompts").rpc("schedule_prefill");
}

/** Stores the composer's work: the create_post arguments plus the editor state to reopen it with. */
export async function saveScheduleDraft(
  supabase: Pick<Client, "schema">,
  slotId: string,
  { post, composer, opensAt, lockAt }: { post: CreatePostParams; composer: Record<string, unknown>; opensAt: string | null; lockAt: string },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("schedule_save_draft", {
    p_slot: slotId,
    p_payload: { post: buildCreatePostArgs(post), composer } as never,
    p_opens_at: opensAt as string,
    p_lock_at: lockAt,
  });
  return { error: error ? promptErrorMessage(error.message) : null };
}

export async function markScheduleReady(supabase: Pick<Client, "schema">, slotId: string): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("schedule_mark_ready", { p_slot: slotId });
  return { error: error ? promptErrorMessage(error.message) : null };
}

export async function unreadyScheduleSlot(supabase: Pick<Client, "schema">, slotId: string): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("schedule_unready", { p_slot: slotId });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/**
 * After a prompt is published straight from Compose, tells the calendar that
 * its slot (if there is one) is covered, so it stops asking for it. Best
 * effort: the post is already live, so a failure here changes nothing for players.
 */
export async function linkScheduleSlot(
  supabase: Pick<Client, "schema">,
  postId: string,
  { kind, season, week, gameId }: { kind: string; season: number; week: number; gameId?: string | null },
): Promise<void> {
  await supabase.schema("prompts").rpc("schedule_link_post", {
    p_post: postId,
    p_kind: kind,
    p_season: season,
    p_week: week,
    ...(gameId ? { p_game_id: gameId } : {}),
  });
}

export async function clearScheduleSlot(supabase: Pick<Client, "schema">, slotId: string): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("schedule_clear", { p_slot: slotId });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/** "Sun, Oct 18, 1:00 PM" in US Eastern, the zone the schedule and the digest speak in. */
export function formatEastern(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));
}

/** An NFL game as the calendar draws it. */
export type CalendarGame = { id: string; kickoff: string; away: string; home: string; primetime: boolean };

export type PostStatus = "open" | "locked" | "resolved" | "void";

export const POST_STATUS_LABELS: Record<PostStatus, string> = { open: "Open", locked: "Locked", resolved: "Resolved", void: "Void" };

/** A published prompt as the calendar draws it. */
export type CalendarPost = {
  id: string;
  template_kind: string;
  template_name: string;
  prompt_text: string;
  status: PostStatus;
  created_at: string;
  lock_at: string;
};

/** Games kicking off in [from, to), earliest first. Read from the same table as the composer's schedule. */
export async function fetchCalendarGames(supabase: Client, from: Date, to: Date): Promise<CalendarGame[]> {
  const { data, error } = await supabase
    .from("nfl_games")
    .select("id, kickoff, away_team, home_team, primetime")
    .gte("kickoff", from.toISOString())
    .lt("kickoff", to.toISOString())
    .order("kickoff")
    .order("id");
  if (error) throw new Error(error.message);
  return data.map((row) => ({ id: row.id, kickoff: row.kickoff, away: row.away_team, home: row.home_team, primetime: row.primetime }));
}

/**
 * Every published prompt that opened or locks in [from, to), whatever its
 * status and however it was made (scheduled or composed straight away). The
 * friends-only list update cards are not prompts an admin plans, so they are
 * left out.
 */
export async function fetchCalendarPosts(supabase: Client, from: Date, to: Date): Promise<CalendarPost[]> {
  const a = from.toISOString();
  const b = to.toISOString();
  const { data, error } = await supabase
    .from("prompt_posts")
    .select("id, template_kind, template_name, prompt_text, status, created_at, lock_at")
    .neq("template_kind", "ranking_update")
    .or(`and(created_at.gte.${a},created_at.lt.${b}),and(lock_at.gte.${a},lock_at.lt.${b})`)
    .order("created_at")
    .limit(500);
  if (error) throw new Error(error.message);
  return data as CalendarPost[];
}

/** "1:00 PM" in US Eastern. */
export function formatEasternTime(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" }).format(new Date(iso));
}

/** "Oct 15" in US Eastern. */
export function formatEasternDay(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", month: "short", day: "numeric" }).format(new Date(iso));
}

/** The calendar day an instant falls on in US Eastern, as YYYY-MM-DD. */
export function easternDate(when: string | Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York" }).format(new Date(when));
}

/** Where a slot opens the composer. */
export function composeHref(slotId: string): string {
  return `/admin/prompts?slot=${slotId}`;
}
