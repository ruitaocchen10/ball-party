/**
 * The analytics opt-out lives in a first-party cookie, not in PostHog's own
 * storage, for two reasons: the server reads it before sending an event from a
 * server action, and `posthog.reset()` (called on sign-out) clears PostHog's
 * stored consent, which would silently turn analytics back on.
 */
export const ANALYTICS_OPT_OUT_COOKIE = "bp_analytics_optout";

const ONE_YEAR_SECONDS = 60 * 60 * 24 * 365;

/** Whether a raw `Cookie` header value or `document.cookie` string carries the opt-out. */
export function hasOptOutCookie(cookieString: string): boolean {
  return cookieString.split(";").some((part) => part.trim() === `${ANALYTICS_OPT_OUT_COOKIE}=1`);
}

/** The `document.cookie` assignment that records (or clears) the opt-out. */
export function optOutCookieString(optedOut: boolean): string {
  return optedOut
    ? `${ANALYTICS_OPT_OUT_COOKIE}=1; Max-Age=${ONE_YEAR_SECONDS}; Path=/; SameSite=Lax`
    : `${ANALYTICS_OPT_OUT_COOKIE}=; Max-Age=0; Path=/; SameSite=Lax`;
}
