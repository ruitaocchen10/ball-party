"use client";

import { useEffect, useState } from "react";

/**
 * Holds a newly received, already-known result for a short visual reveal.
 * By default the initial key is immediately visible, so a reload need not
 * replay a moment the player may already have watched. A caller may opt into
 * concealing that first result when entering a game is itself the reveal.
 * The caller, not animation events, owns the revealed state so reduced-motion
 * remains correct.
 */
export function useTimedReveal(revealKey: string, delayMs: number, initiallyRevealed: boolean = true): { revealed: boolean } {
  const [revealedKey, setRevealedKey] = useState<string | null>(() => initiallyRevealed ? revealKey : null);
  const revealed = revealedKey === revealKey;

  useEffect(() => {
    if (revealed) return;
    const timeout = setTimeout(() => setRevealedKey(revealKey), delayMs);
    return () => clearTimeout(timeout);
  }, [delayMs, revealKey, revealed]);

  return { revealed };
}
