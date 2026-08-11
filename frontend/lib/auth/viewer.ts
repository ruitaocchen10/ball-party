export function isSignedInViewer(
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
): claims is { sub: string; is_anonymous?: boolean } {
  return Boolean(claims?.sub);
}

export function isGuestViewer(claims: { is_anonymous?: boolean } | null | undefined) {
  return claims?.is_anonymous === true;
}
