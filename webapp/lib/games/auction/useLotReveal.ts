"use client";

import { useTimedReveal } from "@/lib/foundation/ui-kit/useTimedReveal";

/**
 * The client-side suspense pause before a new lot's player appears. Every
 * lot's identity is already dealt server-side and present in the client's
 * `lots` state the moment a match loads (see `LotStrip`'s doc comment) --
 * this hook doesn't decide anything or hide any data, it only sits on a
 * value the caller already has for `delayMs` before letting the caller
 * reveal it. Modeled directly on sabotage draft's `useTurnReveal`, which
 * makes the same trade for its turn-reel animation.
 *
 * Driving the concealed/revealed swap from this hook's state (rather than
 * from whether some CSS/JS animation happens to have finished) is what
 * makes it correct regardless of motion preference: a `prefers-reduced-motion`
 * viewer or a test environment never runs the animation, but still gets the
 * right outcome once `delayMs` elapses.
 */
// Keep the reel's cadence aligned with Sabotage Draft's turn spin. The
// auction's preview phase is five seconds, so this still leaves a beat to
// read the newly revealed lot before bidding begins.
export const LOT_REVEAL_MS = 3_000;

/**
 * `lotKey` should be a string that changes exactly when the current lot
 * does -- e.g. `String(turn.currentLot)` -- the same value the caller
 * already keys other per-lot state off of.
 */
export function useLotReveal(lotKey: string, delayMs: number = LOT_REVEAL_MS): { revealed: boolean } {
  return useTimedReveal(lotKey, delayMs);
}
