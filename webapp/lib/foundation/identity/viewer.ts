export function isSignedInViewer(
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
): claims is { sub: string; is_anonymous?: boolean } {
  return Boolean(claims?.sub);
}

export function isGuestViewer(claims: { is_anonymous?: boolean } | null | undefined) {
  return claims?.is_anonymous === true;
}

/** A guest has a real session for playing, but only an account holder may host. */
export function canCreateLobby(
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
): boolean {
  return isSignedInViewer(claims) && !isGuestViewer(claims);
}

/** Profiles are a durable account feature; guest identities only last for a game. */
export function canViewProfile(
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
): boolean {
  return isSignedInViewer(claims) && !isGuestViewer(claims);
}

/** What the header and sidebar show about the viewer. All null reads as signed out. */
export type ChromeIdentity = { displayName: string | null; email: string | null; avatarUrl: string | null };

/**
 * The identity the header and sidebar show, decided in one place.
 *
 * Only a credentialed account is shown as someone: a guest has a real session
 * for playing but no account, and its profile row is a placeholder ("Player")
 * that lives a month at most. Showing it in the account menu would offer a
 * profile and settings the guest cannot open, so a guest reads as signed out —
 * the header's "Sign in" is also how a guest reaches an account. Gameplay is
 * unaffected: pages keep using `isSignedInViewer` for that.
 */
export function chromeIdentity(
  claims: { sub?: string; is_anonymous?: boolean; email?: unknown } | null | undefined,
  profile: { display_name?: string | null; avatar_url?: string | null } | null | undefined,
): ChromeIdentity {
  if (!canViewProfile(claims)) return { displayName: null, email: null, avatarUrl: null };
  const email = typeof claims?.email === "string" ? claims.email : null;
  return {
    displayName: profile?.display_name ?? email,
    email,
    avatarUrl: profile?.avatar_url ?? null,
  };
}

/**
 * The Huddle itself is public, but only credentialed accounts may answer or
 * comment. prompts.submit_response and prompts.post_comment enforce the same
 * boundary server-side (see 20260909121500_0095_prompts_write_api.sql), so a
 * temporary player never reaches a control the database will refuse anyway.
 */
export function canAnswerPrompt(
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
): boolean {
  return isSignedInViewer(claims) && !isGuestViewer(claims);
}
