"use client";

import { useEffect, useState, useSyncExternalStore } from "react";

/**
 * The staged reveal of a finished season follows its visual order: score,
 * stat line, awards, record, playoffs, then the supporting details. This
 * prevents a later reveal from inserting above content already on screen.
 *
 * Like the auction's `useLotReveal`, this
 * hook decides nothing about the season and hides no data the caller doesn't
 * already hold: the whole result is in hand from the first render, and all this
 * does is say how much of it to draw yet. That is what keeps it correct for a
 * `prefers-reduced-motion` viewer or a test, where no animation ever runs.
 */
export const REVEAL_STAGES = [
  "score",
  "stat_line",
  "awards",
  "record",
  "playoffs",
  "details",
] as const;
export type RevealStage = (typeof REVEAL_STAGES)[number];

/** How long each stage holds before the next one lands. */
export const REVEAL_STEP_MS = 1600;

const LAST_STAGE = REVEAL_STAGES.length - 1;

/**
 * Whether this browser has already watched a run's reveal through.
 *
 * The reveal is a moment, not a page: played once when the run finishes, it
 * should not start over on every reload of the same URL. The run itself is the
 * server's and reopens read-only from its URL; only "have I watched this?" is
 * per-browser, so it lives in localStorage. It is a convenience — blocked or
 * cleared storage, or a second device, only costs a replay.
 */
const key = (matchId: string) => `qb-season-builder:revealed:${matchId}`;

export function hasSeenReveal(matchId: string): boolean {
  try {
    return localStorage.getItem(key(matchId)) === "1";
  } catch {
    return false;
  }
}

export function markRevealSeen(matchId: string): void {
  try {
    localStorage.setItem(key(matchId), "1");
  } catch {
    // Blocked storage only costs a replay.
  }
}

/** Nothing about what this browser has watched changes under a mounted screen. */
const noSubscription = () => () => {};

export type SeasonReveal = {
  /** Whether `stage` has been reached, and so should be drawn. */
  shows: (stage: RevealStage) => boolean;
  /** Still playing: there is more to come, and it can be skipped. */
  playing: boolean;
  skip: () => void;
};

/**
 * `staged` is false for a result nobody is watching land — the public page —
 * which draws the whole season at once and remembers nothing.
 */
export function useSeasonReveal(matchId: string, staged: boolean): SeasonReveal {
  // Read after hydration: the server has no idea what this browser has watched.
  const seen = useSyncExternalStore(noSubscription, () => hasSeenReveal(matchId), () => false);
  const [stage, setStage] = useState(0);
  const [skipped, setSkipped] = useState(false);

  const playing = staged && !seen && !skipped && stage < LAST_STAGE;
  const reached = playing ? stage : LAST_STAGE;

  useEffect(() => {
    if (!playing) return;
    const timeout = setTimeout(() => setStage((current) => current + 1), REVEAL_STEP_MS);
    return () => clearTimeout(timeout);
  }, [playing, stage]);

  // Watched through or skipped, it does not play again in this browser.
  useEffect(() => {
    if (staged && !playing) markRevealSeen(matchId);
  }, [staged, playing, matchId]);

  return {
    shows: (name) => REVEAL_STAGES.indexOf(name) <= reached,
    playing,
    skip: () => setSkipped(true),
  };
}
