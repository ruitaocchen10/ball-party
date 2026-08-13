/** Routes an anonymous player through the same-origin sign-out endpoint. */
export function guestSessionFinishedHref(next: string): string {
  return `/auth/guest-session-finished?next=${encodeURIComponent(next)}`;
}
