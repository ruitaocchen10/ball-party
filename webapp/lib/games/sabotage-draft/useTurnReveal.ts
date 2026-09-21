"use client";

import { useTimedReveal } from "@/lib/foundation/ui-kit/useTimedReveal";

/**
 * The client-side "the system is choosing" pause between one sabotage draft
 * turn and the next. Every round's franchises are already fully dealt
 * server-side before any client sees them (see
 * sabotage_draft_private.deal_board) -- this hook doesn't decide anything,
 * it only sits on a value the caller already has for `delayMs` before
 * letting the caller reveal it, the same trade the turn panel's reel
 * animation already made when it was purely decorative.
 *
 * This is also what makes the reel trustworthy regardless of whether any
 * animation actually plays. Before this hook existed, the reel's "resting on
 * the right team" state was a side effect of a CSS keyframe animation
 * finishing -- which never happens for a `prefers-reduced-motion` viewer (or
 * a test/snapshot environment, which never runs CSS animations either), so
 * that reel sat frozen on whichever decoy happened to render first. A caller
 * driven by `revealed` instead has one explicit idle state -- "not yet
 * revealed" -- that renders correctly with no animation involved at all;
 * motion is layered on top of that state as an enhancement, not load-bearing
 * for correctness.
 */
export const TURN_REVEAL_MS = 3_000;

/**
 * `turnKey` should be a string that changes exactly when the underlying turn
 * does -- e.g. `${round_number}-${active_user_id}` -- the same tuple the
 * caller already keys other per-turn state off of.
 */
export function useTurnReveal(turnKey: string, delayMs: number = TURN_REVEAL_MS): { revealed: boolean } {
  return useTimedReveal(turnKey, delayMs);
}
