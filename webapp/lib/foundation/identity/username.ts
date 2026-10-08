/**
 * Client-side helpers for usernames. The rules themselves (length, characters,
 * reserved names, uniqueness) live in SQL (`claim_username`, `username_available`,
 * migration 0183); nothing here is authoritative. The format check only exists
 * so the field can say "too short" without a round trip.
 */
export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;
export const USERNAME_HINT = `${USERNAME_MIN}–${USERNAME_MAX} letters, numbers or underscores.`;

/** A hint for what's wrong with the shape of a username, or null when it looks fine. */
export function usernameFormatHint(value: string): string | null {
  if (value.length < USERNAME_MIN) return `Usernames are at least ${USERNAME_MIN} characters.`;
  if (value.length > USERNAME_MAX) return `Usernames are at most ${USERNAME_MAX} characters.`;
  if (!/^[A-Za-z0-9_]+$/.test(value)) return "Use only letters, numbers and underscores.";
  return null;
}

/** Maps the Postgres errors raised by `claim_username` to player-facing copy. */
export function usernameClaimError(error: { message?: string; code?: string } | null | undefined): string {
  const message = error?.message ?? "";
  if (message.includes("username_taken")) return "That username is taken.";
  if (message.includes("username_reserved")) return "That username isn’t available.";
  if (message.includes("invalid_username")) return USERNAME_HINT;
  if (message.includes("rate_limited")) return "You’re changing your username too often. Try again later.";
  if (message.includes("guests_cannot_have_username")) return "Create an account to pick a username.";
  return "We couldn’t save that username. Please try again.";
}

/**
 * There is no server-side "has confirmed" flag, so the one-time prompt for
 * accounts that were given a generated username is dismissed per browser.
 */
const confirmedKey = (userId: string) => `bp.username-confirmed.${userId}`;

export function isUsernameConfirmed(userId: string): boolean {
  try {
    return window.localStorage.getItem(confirmedKey(userId)) === "1";
  } catch {
    // Storage blocked: treat as confirmed so we never nag on every page load.
    return true;
  }
}

export function markUsernameConfirmed(userId: string) {
  try {
    window.localStorage.setItem(confirmedKey(userId), "1");
  } catch {
    // Nothing to do; the prompt may show again.
  }
}
