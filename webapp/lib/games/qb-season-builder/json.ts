/**
 * The little that reading this game's untyped jsonb needs, shared by the board
 * and the saved result so the two parsers agree on what a malformed row is.
 */

export type JsonObject = { [key: string]: unknown };

export function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Every named field of `json` as a number, or null when any is missing. */
export function numbers<K extends string>(json: unknown, keys: readonly K[]): Record<K, number> | null {
  if (!isObject(json)) return null;
  const out = {} as Record<K, number>;
  for (const key of keys) {
    const value = json[key];
    if (typeof value !== "number") return null;
    out[key] = value;
  }
  return out;
}
