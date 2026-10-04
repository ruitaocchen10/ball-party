/**
 * Pure helpers shared across prompt templates: scoring a slot response
 * against ground truth, and small display formatting. Kept out of any one
 * template component because this is data shaping, not layout.
 */

import type { Option, Post, Slot } from "@/lib/foundation/content/prompts/types";

export type SlotResult = {
  correctCount: number;
  total: number;
  pointsEarned: number;
  fullyCorrect: boolean;
};

/** Scores one slot's response against its ground truth. Undefined until `slot.correct` is set. */
export function scoreSlot(slot: Slot, response: string[] | undefined): SlotResult | null {
  // An empty answer is a no-contest slot (a tied game): nothing to score either way.
  if (!slot.correct || slot.correct.length === 0 || !response || response.length === 0) return null;

  if (slot.shape === "pick") {
    const correctCount = response[0] === slot.correct[0] ? 1 : 0;
    return { correctCount, total: 1, pointsEarned: correctCount ? slot.points : 0, fullyCorrect: correctCount === 1 };
  }

  if (slot.shape === "pick_set") {
    const total = slot.correct.length;
    const correctCount = response.filter((id) => slot.correct!.includes(id)).length;
    const pointsEarned = Math.round((slot.points * correctCount) / total);
    return { correctCount, total, pointsEarned, fullyCorrect: correctCount === total };
  }

  // rank: credit for each position that matches the true order exactly.
  const total = slot.correct.length;
  const correctCount = response.filter((id, i) => slot.correct![i] === id).length;
  const pointsEarned = Math.round((slot.points * correctCount) / total);
  return { correctCount, total, pointsEarned, fullyCorrect: correctCount === total };
}

/**
 * Whether a slot's answer is known yet. Slots of a multi-game Picks post are
 * graded one at a time as each game goes final (0117), so this — not the
 * post's status — decides whether a pick can be shown as right or wrong.
 */
export function isSlotGraded(slot: Pick<Slot, "correct">): boolean {
  return (slot.correct?.length ?? 0) > 0;
}

/** A graded slot with no right answer: a tied game on a weekly slate (0174). Everyone earned 0 on it. */
export function isSlotNoContest(slot: Pick<Slot, "correct">): boolean {
  return slot.correct !== undefined && slot.correct.length === 0;
}

/** `picks` is legacy (backfilled to `weekly_picks` by 0173) but still allowed by the database — see types.ts's TemplateKind. */
export function isPicksPost(post: Pick<Post, "templateKind">): boolean {
  return post.templateKind === "picks" || post.templateKind === "game_pick" || post.templateKind === "weekly_picks";
}

/**
 * The Huddle search bar's match rule: a case-insensitive substring over a
 * post's prompt text, caption, and author. Shared between the server's
 * `?q=` render (no-JS and crawlers) and the client's live filter as the
 * viewer types, so the two never drift apart.
 */
export function matchesSearchQuery(post: Pick<Post, "promptText" | "caption" | "author">, query: string): boolean {
  const normalized = query.trim().toLocaleLowerCase();
  if (!normalized) return true;
  return `${post.promptText} ${post.caption} ${post.author}`.toLocaleLowerCase().includes(normalized);
}

/**
 * The client-side counterpart to `prompts.submit_response`'s authoritative
 * lock check. A post can remain stored as `open` after its deadline passes,
 * so the status alone must never decide whether to offer a pick form.
 */
export function isPromptOpenForAnswers(post: Pick<Post, "status" | "lockAt">, now = Date.now()): boolean {
  const lockAt = new Date(post.lockAt).getTime();
  return post.status === "open" && Number.isFinite(lockAt) && lockAt > now;
}

/** How many candidates a pick-one prompt's art has room for. */
export const COVER_OPTION_LIMIT = 4;

/**
 * The candidates a pick-one prompt's art shows: the ones the admin placed
 * (`coverPosition`, in that order), or — for a pool small enough to show whole,
 * and for prompts published before the admin could choose — the first few.
 */
export function coverOptions(options: Option[]): Option[] {
  const placed = options.filter((option) => option.coverPosition !== undefined).sort((left, right) => left.coverPosition! - right.coverPosition!);
  return (placed.length ? placed : options).slice(0, COVER_OPTION_LIMIT);
}

/** A pool bigger than the art, with the admin's choice of exactly four still to be made. */
export function needsCoverChoice(options: Option[]): boolean {
  return options.length > COVER_OPTION_LIMIT && options.filter((option) => option.coverPosition !== undefined).length !== COVER_OPTION_LIMIT;
}

/** Total points a post has paid out, or null while anything remains unresolved. */
export function totalPoints(post: Post): number | null {
  if (post.status !== "resolved") return null;
  let sum = 0;
  for (const slot of post.slots) {
    const result = scoreSlot(slot, post.viewerResponse?.[slot.id]);
    if (!result) return null;
    sum += result.pointsEarned;
  }
  return sum;
}

/** An option already spent in one of a slot's excluded sibling slots can't be picked again — the preseason-picks constraint. */
export function isOptionTakenElsewhere(
  slot: Slot,
  optionId: string,
  responses: Record<string, string[]>,
): boolean {
  if (!slot.excludesSlotIds) return false;
  return slot.excludesSlotIds.some((otherId) => responses[otherId]?.includes(optionId));
}

export function relativeTime(iso: string): string {
  const diffMs = new Date(iso).getTime() - Date.now();
  const abs = Math.abs(diffMs);
  const hours = Math.round(abs / 3600_000);
  if (hours < 1) return diffMs < 0 ? "just now" : "in a few min";
  if (hours < 24) return diffMs < 0 ? `${hours}h ago` : `in ${hours}h`;
  const days = Math.round(hours / 24);
  return diffMs < 0 ? `${days}d ago` : `in ${days}d`;
}

export function initials(name: string): string {
  return name.trim().slice(0, 1).toUpperCase();
}

function hashString(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  return hash % 100;
}

/**
 * Stands in for "the pipeline's live aggregate" the moment a viewer answers
 * an open slot with no pre-seeded aggregate — deterministic, not random, so
 * the same pick always reveals the same breakdown.
 */
export function synthesizeAggregate(slot: Slot, response: string[]): Record<string, number> {
  const result: Record<string, number> = {};

  if (slot.shape === "pick") {
    const chosen = response[0];
    const rest = slot.options.filter((o) => o.id !== chosen);
    const chosenPct = 45 + hashString(chosen) % 20;
    result[chosen] = chosenPct;
    const remaining = 100 - chosenPct;
    rest.forEach((o) => {
      result[o.id] = rest.length ? Math.round(remaining / rest.length) : 0;
    });
    return result;
  }

  // pick_set / rank: "percent of respondents who included this option," not
  // mutually exclusive, so these don't need to sum to 100.
  slot.options.forEach((o) => {
    const included = response.includes(o.id);
    result[o.id] = included ? 30 + (hashString(o.id) % 40) : 5 + (hashString(o.id) % 20);
  });
  return result;
}
