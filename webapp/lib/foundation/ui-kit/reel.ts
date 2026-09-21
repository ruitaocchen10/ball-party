/**
 * Picks a stable run of decoys for a reel. It deliberately avoids random
 * selection: a client component can render on both server and browser, and
 * the two renders must produce the same rows for hydration to succeed.
 */
export function stableReelDecoys<T>(items: readonly T[], key: string, count: number): T[] {
  if (count <= 0 || items.length === 0) return [];

  let hash = 0;
  for (let index = 0; index < key.length; index++) hash = (hash * 31 + key.charCodeAt(index)) >>> 0;
  const start = hash % items.length;
  const length = Math.min(count, items.length);
  return Array.from({ length }, (_, index) => items[(start + index) % items.length]!);
}
