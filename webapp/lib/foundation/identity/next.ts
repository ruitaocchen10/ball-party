/**
 * Where to send someone once they're authenticated.
 *
 * Only ever a path on our own origin. Without this, `next` is an open redirect:
 * an attacker sends a login link that hands the freshly authenticated user off
 * to a site they control.
 *
 * `origin` is optional because the two shapes arrive from different places. A
 * form field carries a bare path. An email link carries whatever Supabase
 * rendered for `{{ .RedirectTo }}`, which is the absolute URL we handed to
 * `emailRedirectTo` — so callers that know their own origin accept that form
 * too, and reduce it back to a path.
 */
export function safeNextPath(value: unknown, origin?: string): string {
  if (typeof value !== "string" || value === "") return "/";

  // A relative path. `//evil.com` is protocol-relative, not a path.
  if (value.startsWith("/") && !value.startsWith("//")) return value;

  if (origin) {
    try {
      const url = new URL(value);
      if (url.origin === origin) return `${url.pathname}${url.search}${url.hash}`;
    } catch {
      // Not a URL at all, so not a destination we'll honour.
    }
  }

  return "/";
}
