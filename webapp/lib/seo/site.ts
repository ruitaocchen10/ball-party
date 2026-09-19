export const SITE_NAME = "Ball Party";

export const SITE_DESCRIPTION =
  "Sports knowledge party games with your friends — weekly NFL picks, Power Rankings, and live games like Higher or Lower.";

/**
 * The canonical origin every absolute URL in metadata, the sitemap and
 * robots.txt is built from. The env value wins so a preview deployment
 * canonicalises to production rather than to its own throwaway host; the
 * literal is the fallback for a production build that forgot to set it.
 */
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL || "https://ballparty.social").replace(/\/$/, "");

/** Collapses whitespace and cuts to `max` characters, ending on an ellipsis when it had to cut. */
export function truncate(text: string, max: number): string {
  const clean = text.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  return `${clean.slice(0, max - 1).trimEnd()}…`;
}
