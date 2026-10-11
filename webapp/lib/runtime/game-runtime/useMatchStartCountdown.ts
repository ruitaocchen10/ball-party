"use client";

import { useEffect, useState } from "react";

import { createClient } from "@/lib/supabase/client";

/** The length of the lead, which is the ring's full circle. The server owns the real value. */
export const START_LEAD_SECONDS = 3;

/** What `match_play_start` returns: when play begins, and the server's clock as of asking. */
export type MatchPlayStart = {
  /** Null when there is nothing to wait for: a solo run. */
  play_starts_at: string | null;
  server_now: string;
};

/**
 * Seconds until play begins by the server's clock, given that `start` was
 * fetched at `fetchedAtMs` on this device and it is `nowMs` there. The server's
 * "now" plus the time that has passed locally since, never the device's own
 * idea of the time. Null when there is no countdown.
 */
export function secondsUntilPlay(start: MatchPlayStart, fetchedAtMs: number, nowMs: number): number | null {
  if (!start.play_starts_at) return null;
  const serverNowMs = Date.parse(start.server_now) + (nowMs - fetchedAtMs);
  return (Date.parse(start.play_starts_at) - serverNowMs) / 1000;
}

/**
 * The number the start countdown shows, or null when none is running.
 *
 * A room match opens with a three-second countdown the server owns: the match
 * carries `play_starts_at`, and every deadline the game set is already pushed
 * back by the same three seconds (`private.begin_match_countdown`). So this
 * only counts down to that instant. Every player sees the same numbers, the
 * first phase is full-length once they reach zero, and someone who opens the
 * match late sees what is left. Asks once, on mount; a failed read just means
 * no countdown, since the match is already running underneath. Same behavior
 * as the iOS `matchStartCountdown` modifier.
 */
export function useMatchStartCountdown(matchId: string): number | null {
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    void (async () => {
      const { data, error } = await createClient().rpc("match_play_start", { p_match_id: matchId });
      if (cancelled || error || !data) return;
      const start = data as MatchPlayStart;
      const fetchedAt = Date.now();

      const tick = () => {
        const remaining = secondsUntilPlay(start, fetchedAt, Date.now());
        if (remaining === null || remaining <= 0) {
          setCount(null);
          return;
        }
        const number = Math.min(START_LEAD_SECONDS, Math.ceil(remaining));
        setCount(number);
        // Wake as the next number is due.
        timer = setTimeout(tick, Math.max(50, (remaining - (number - 1)) * 1000));
      };
      tick();
    })();

    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [matchId]);

  return count;
}
