"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/**
 * The behaviours every timer-driven match screen needs, in one place.
 *
 * The auction learned these the hard way — see its match component's history
 * for the playtest where three lots in one game took 81s, 127s and 271s, one
 * of them with no player action at all. The architecture doc calls this out
 * by name: "a deadline the client owns isn't a rule... the auction settles
 * this shape first, and the other timer-driven games should lift it rather
 * than reinvent it." This module is that lift.
 *
 * It knows nothing about any game. It takes the two game-specific RPCs —
 * expiry and a full state re-read — as parameters, and drives them from a
 * single deadline the caller resolves from its own state.
 *
 * 1. **The countdown.** `remainingMs` counts down to `deadline` minus
 *    `visibleSlackMs`, so a move sent as the visible bar empties still has
 *    real deadline behind it against network latency. Slack is the caller's
 *    call, not this module's: a phase nobody can act in (a reveal, a preview)
 *    has nothing to protect and passes 0.
 *
 * 2. **Expiry, asked for repeatedly.** A client that fires exactly once and
 *    latches is the bug that produced the playtest above — one no-op (a clock
 *    a millisecond fast, a network blip) and nobody ever asks again until the
 *    janitor sweeps the match a minute later. This asks again every
 *    `RETRY_MS` for as long as the deadline stays past, with jitter so
 *    several idle clients don't stampede the endpoint in the same tick. Being
 *    wrong is free: the server re-checks in its own time and no-ops if it
 *    disagrees. `skipExpiry` lets a caller exempt the one client mid-decision
 *    (the auction's player on the clock) from asking at all.
 *
 * 3. **A heartbeat, if the caller asks for one.** Off by default, because the
 *    auction's expiry endpoint learns nothing from being asked early. Higher
 *    or Lower's does: its tick RPC stamps the caller as last seen, and a
 *    player who ticks nowhere inside a question is latched absent at that
 *    question's reveal, so that screen has to put the question on a cadence
 *    rather than only once a deadline is past. What the server makes of the
 *    extra asking is the game's business; this only knows how often to ask.
 *
 * 4. **Reconciliation.** Realtime is the fast path, not the only path: a
 *    single dropped payload must not leave the screen permanently wrong. This
 *    calls `reconcile` — a full state re-read — under two of the three
 *    conditions the architecture doc asks for: a deadline that stays past
 *    long enough (`STALE_MS`) to distrust expiry, and the tab returning to
 *    the foreground, where background throttling means the countdown above
 *    may have barely run. The third condition, a realtime channel rejoin, is
 *    necessarily wired by the caller — only the game's own subscription knows
 *    when that happens — and should call the `reconcile` this hook returns,
 *    the same function driving the other two.
 */

/** How far before the real deadline the visible countdown reaches zero.
 *  Callers pass this (or 0) as `visibleSlackMs`; it lives here so every game
 *  agrees on what "slightly before" means. */
export const VISIBLE_SLACK_MS = 500;

/** How often the countdown itself updates. Exported so a caller's own visible
 *  bar can animate at the same cadence rather than guessing a number. */
export const TICK_MS = 100;

/** How often a client re-asks the server to expire a deadline that has
 *  passed. Asking again is free — the server re-checks under the match lock
 *  and does nothing if it disagrees — so this is tuned for responsiveness,
 *  not caution. */
const RETRY_MS = 1_000;

/** How often a caller that wants a heartbeat asks while the deadline is still
 *  ahead. Comfortably inside Higher or Lower's twelve-second call phase, so
 *  several beats land in every question and losing one to a dropped request
 *  does not make a present player look departed. */
export const HEARTBEAT_MS = 3_000;

/** How far past a deadline the screen has to look before it stops believing
 *  itself and reconciles. Well behind RETRY_MS, so this only fires once
 *  expiry has already had several tries. */
const STALE_MS = 4_000;

export type MatchClockOptions = {
  /** Server time as of the most recently applied state, ISO-formatted. Used
   *  to measure the offset between this browser's clock and the server's, so
   *  the countdown reflects the server's truth rather than the client's. Feed
   *  a fresh value in as new state arrives — from the initial render, from an
   *  RPC response, from a realtime payload — so a machine whose clock drifts
   *  mid-match keeps correcting itself. */
  serverNow: string;
  /** The deadline currently in force, ISO-formatted, or null when nothing is
   *  timed right now (including "the match is over" — a finished match has
   *  no deadline to chase, whatever a stale turn record still says). */
  deadline: string | null;
  /** Subtracted from `deadline` before computing `remainingMs`. Defaults to
   *  0 — a phase nobody can act in has no latency to protect against. Pass
   *  `VISIBLE_SLACK_MS` for a phase a move can be sent in. */
  visibleSlackMs?: number;
  /** True to skip firing expiry from this client entirely — the auction's
   *  player on the clock, for instance, who is the one client that cannot be
   *  trusted with it. Everyone else keeps asking. */
  skipExpiry?: boolean;
  /** How often to call `expire` while the deadline is still ahead. Omit —
   *  the default — for a game whose expiry endpoint learns nothing from being
   *  asked early. Pass `HEARTBEAT_MS` for one whose server reads presence off
   *  the same call. */
  heartbeatMs?: number | null;
  /** Calls the game's expiry RPC and applies whatever it returns. Resolves
   *  once the round trip (and any resulting state application) is done; its
   *  return value is not inspected; a rejection is not caught here, the same
   *  as the code this replaces. */
  expire: () => Promise<unknown> | unknown;
  /** Re-reads the game's full state from the server and applies it. Driven
   *  internally by the watchdog and by the tab regaining focus, and returned
   *  below so the caller's own realtime subscription can drive it too, on
   *  channel rejoin. */
  reconcile: () => Promise<unknown> | unknown;
};

export function useMatchClock({
  serverNow,
  deadline,
  visibleSlackMs = 0,
  skipExpiry = false,
  heartbeatMs = null,
  expire,
  reconcile,
}: MatchClockOptions): { remainingMs: number | null; reconcile: () => void } {
  // How far this browser's clock is from the server's. Re-measured every time
  // a fresh `serverNow` arrives, which is also the only thing the ticking
  // effect below depends on — restarting the interval on a state update is
  // cheap and self-correcting, not a bug.
  const offset = useRef(0);
  const [now, setNow] = useState(0);

  useEffect(() => {
    offset.current = Date.parse(serverNow) - Date.now();
    const tick = () => setNow(Date.now() + offset.current);
    tick();
    const id = setInterval(tick, TICK_MS);
    return () => clearInterval(id);
  }, [serverNow]);

  const deadlineMs = deadline ? Date.parse(deadline) : null;
  const remainingMs =
    deadlineMs === null || now === 0 ? null : Math.max(0, deadlineMs - visibleSlackMs - now);

  // Jitter and the last-attempt clock both reset whenever the deadline itself
  // changes -- a fresh deadline is always a fresh thing to time, never a
  // continuation of the last one.
  const attempted = useRef(0);
  const jitter = useRef(0);
  useEffect(() => {
    jitter.current = 300 + Math.random() * 500;
    attempted.current = 0;
  }, [deadline]);

  // One cadence, chosen by whether the deadline has passed: the retry interval
  // once it has, the caller's heartbeat until then. Sharing `attempted` across
  // both is what keeps a beat and a retry from doubling up at the boundary, and
  // its reset above is why a fresh phase is asked about immediately -- which a
  // heartbeat caller wants, since that ask is what puts everyone on the record
  // as present for the question that just opened.
  //
  // Nothing timed means nothing to ask about, heartbeat or not. A finished
  // match has no deadline, and a screen that kept beating at one would be
  // asking a server that has stopped listening.
  useEffect(() => {
    if (deadlineMs === null || now === 0 || skipExpiry) return;
    const passed = now >= deadlineMs + jitter.current;
    const interval = passed ? RETRY_MS : heartbeatMs;
    if (interval === null) return;
    if (now - attempted.current < interval) return;
    attempted.current = now;
    void expire();
  }, [now, deadlineMs, skipExpiry, heartbeatMs, expire]);

  // The watchdog. Expiry above is the mechanism; this is the admission that it
  // might not have worked -- because a tab was backgrounded and its interval
  // throttled, because a realtime payload never arrived, or because every
  // client eligible to ask is the one this deadline exempted. It only runs
  // once a deadline is well past, so a healthy match never reaches it.
  const reconciled = useRef(0);
  useEffect(() => {
    if (deadlineMs === null || now === 0) return;
    if (now < deadlineMs + STALE_MS) return;
    if (now - reconciled.current < STALE_MS) return;
    reconciled.current = now;
    void reconcile();
  }, [now, deadlineMs, reconcile]);

  // Coming back to a tab is the other moment a screen is likely to be wrong:
  // background throttling means the clock above may have barely run at all.
  // Unconditional -- unlike the watchdog, this doesn't wait for a deadline to
  // be in force, since a foregrounded tab is worth reconciling regardless.
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === "visible") void reconcile();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [reconcile]);

  // Handed back so a caller's realtime subscription can drive the same
  // reconciliation on channel rejoin -- the third of the three conditions,
  // and the one only the caller's own subscription can know has happened.
  const triggerReconcile = useCallback(() => void reconcile(), [reconcile]);

  return { remainingMs, reconcile: triggerReconcile };
}
