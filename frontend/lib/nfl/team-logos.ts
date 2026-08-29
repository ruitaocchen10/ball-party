/**
 * nflverse-style abbreviations mapped to the Pro Football Reference codes
 * used by the shared team-logo bucket. Historic labels resolve to their
 * current franchise asset so every game can remain text-first when a code is
 * unfamiliar.
 */
const LOGO_CODE: Record<string, string> = {
  ARI: "crd", ATL: "atl", BAL: "rav", BUF: "buf", CAR: "car", CHI: "chi",
  CIN: "cin", CLE: "cle", DAL: "dal", DEN: "den", DET: "det", GB: "gnb",
  HOU: "htx", IND: "clt", JAX: "jax", KC: "kan", LA: "ram", LAR: "ram",
  LAC: "sdg", LV: "rai", MIA: "mia", MIN: "min", NE: "nwe", NO: "nor",
  NYG: "nyg", NYJ: "nyj", OAK: "rai", PHI: "phi", PIT: "pit", SEA: "sea",
  SF: "sfo", SD: "sdg", STL: "ram", TB: "tam", TEN: "oti", WAS: "was",
};

/** Returns null for an unexpected pool code so callers can remain text-first. */
export function teamLogoCode(team: string): string | null {
  return LOGO_CODE[team.toUpperCase()] ?? null;
}

/**
 * Public URL for a franchise logo in the shared `team-logos` bucket. Callers
 * render it optimistically and fall back to text when a historic or future
 * code has no uploaded file.
 */
export function franchiseLogoUrl(code: string): string {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/team-logos/${code}.png`;
}
