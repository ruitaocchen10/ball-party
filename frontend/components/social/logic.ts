/**
 * PROTOTYPE — throwaway. Pure helpers shared by all three variants: scoring a
 * slot response against ground truth, and small display formatting. Kept out
 * of any one variant because this is data shaping, not layout — the thing the
 * prototype skill's anti-patterns call out as fine to share.
 */

import type { Post, Slot } from "./types";

export type SlotResult = {
  correctCount: number;
  total: number;
  pointsEarned: number;
  fullyCorrect: boolean;
};

/** Scores one slot's response against its ground truth. Undefined until `slot.correct` is set. */
export function scoreSlot(slot: Slot, response: string[] | undefined): SlotResult | null {
  if (!slot.correct || !response || response.length === 0) return null;

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

/** `game_pick` and `weekly_picks` remain readable for posts created before Picks unified them — see types.ts's TemplateKind. */
export function isPicksPost(post: Pick<Post, "templateKind">): boolean {
  return post.templateKind === "picks" || post.templateKind === "game_pick" || post.templateKind === "weekly_picks";
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
