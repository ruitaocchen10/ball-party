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

/**
 * Prompt composers are configured by the server-only comma-separated
 * PROMPTS_ADMIN_EMAILS list. ADMIN_EMAIL remains a fallback for the older
 * single-admin setup. Neither value is shipped to the browser.
 */
export function isAdminViewer(claims: { email?: string } | null | undefined): boolean {
  const configured = process.env.PROMPTS_ADMIN_EMAILS ?? process.env.ADMIN_EMAIL ?? "";
  const adminEmails = configured.split(",").map((email) => email.trim().toLowerCase()).filter(Boolean);
  return Boolean(claims?.email && adminEmails.includes(claims.email.toLowerCase()));
}
