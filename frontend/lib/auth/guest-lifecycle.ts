/**
 * A guest only keeps their anonymous identity while a party continues. Once
 * the host returns everyone to the lobby, the next visit starts as a new
 * guest unless the player has created an account.
 */
export function shouldResetGuestSession({
  isGuest,
  postGameChoice,
}: {
  isGuest: boolean;
  postGameChoice: "replay" | "lobby";
}): boolean {
  return isGuest && postGameChoice === "lobby";
}

export function guestSessionFinishedHref(next: string): string {
  return `/auth/guest-session-finished?next=${encodeURIComponent(next)}`;
}
