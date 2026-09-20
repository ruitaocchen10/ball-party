/**
 * nflverse's headshot URLs point at NFL.com's image CDN in its original
 * 3400px form (several MB each). The CDN resizes on request through the
 * transformation segment of the path, for both the `/upload/` and `/private/`
 * forms nflverse mixes. A URL that doesn't match — another host, or a shape
 * the CDN may add later — is returned untouched rather than guessed at.
 *
 * `f_png` is pinned instead of `f_auto` so the export always gets a PNG with
 * its transparent background, whatever the requesting browser accepts.
 */
export function resizedHeadshotUrl(url: string, width: number): string {
  return url.replace(/\/(upload|private)\/f_auto,q_auto\//, `/$1/f_png,q_auto,w_${width}/`);
}
