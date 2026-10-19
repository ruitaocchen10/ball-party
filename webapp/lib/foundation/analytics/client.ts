import posthog from "posthog-js";

import { hasOptOutCookie, optOutCookieString } from "@/lib/foundation/analytics/consent";
import type { AnalyticsEventName, AnalyticsEvents } from "@/lib/foundation/analytics/events";

/**
 * Browser-side analytics. Every function here is a quiet no-op when PostHog was
 * never initialised (no key configured, server render, a blocker) and swallows
 * its own errors: analytics must never be the reason a tap does nothing.
 *
 * Server actions that end in a redirect send their events from
 * `./server.ts` instead; the page that follows the redirect has no hook to
 * report them from.
 */

function ready(): boolean {
  return typeof window !== "undefined" && posthog.__loaded === true;
}

export function track<E extends AnalyticsEventName>(event: E, props: AnalyticsEvents[E]): void {
  if (!ready()) return;
  try {
    posthog.capture(event, props);
  } catch {
    // Analytics failures are never the player's problem.
  }
}

/** Ties this browser's events to the Supabase user. Called for guests too, flagged as such. */
export function identify(userId: string, traits: { is_guest: boolean }): void {
  if (!ready()) return;
  try {
    if (posthog.get_distinct_id() === userId) return;
    posthog.identify(userId, traits);
  } catch {
    // See track().
  }
}

/** Forgets who this browser was. `reset()` also clears consent, so re-apply the cookie's. */
export function resetIdentity(): void {
  if (!ready()) return;
  try {
    posthog.reset();
    applyConsent(isOptedOut());
  } catch {
    // See track().
  }
}

export function isOptedOut(): boolean {
  return typeof document !== "undefined" && hasOptOutCookie(document.cookie);
}

/** Records the choice in the cookie the server reads, and tells PostHog. */
export function setOptedOut(optedOut: boolean): void {
  document.cookie = optOutCookieString(optedOut);
  if (!ready()) return;
  try {
    applyConsent(optedOut);
  } catch {
    // See track().
  }
}

function applyConsent(optedOut: boolean): void {
  if (optedOut) posthog.opt_out_capturing();
  else posthog.opt_in_capturing({ captureEventName: false });
}
