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
