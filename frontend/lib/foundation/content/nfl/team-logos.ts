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

/** Primary franchise colors for the social matchup tiles. Historic codes share their current club's color. */
const PRIMARY_COLOR: Record<string, string> = {
  ARI: "#97233f", ATL: "#a71930", BAL: "#241773", BUF: "#00338d",
  CAR: "#0085ca", CHI: "#0b162a", CIN: "#fb4f14", CLE: "#311d00",
  DAL: "#003594", DEN: "#fb4f14", DET: "#0076b6", GB: "#203731",
  HOU: "#03202f", IND: "#002c5f", JAX: "#006778", KC: "#e31837",
  LA: "#003594", LAR: "#003594", LAC: "#0080c6", LV: "#000000",
  MIA: "#008e97", MIN: "#4f2683", NE: "#002244", NO: "#d3bc8d",
  NYG: "#0b2265", NYJ: "#125740", OAK: "#000000", PHI: "#004c54",
  PIT: "#ffb612", SEA: "#002244", SF: "#aa0000", SD: "#0080c6",
  STL: "#003594", TB: "#d50a0a", TEN: "#0c2340", WAS: "#5a1414",
};

/** Returns null for an unexpected pool code so callers can remain text-first. */
export function teamLogoCode(team: string): string | null {
  return LOGO_CODE[team.toUpperCase()] ?? null;
}

/** Returns a franchise's primary color when the code is known. */
export function teamPrimaryColor(team: string): string | null {
  return PRIMARY_COLOR[team.toUpperCase()] ?? null;
}

/**
 * Public URL for a franchise logo in the shared `team-logos` bucket. Callers
 * render it optimistically and fall back to text when a historic or future
 * code has no uploaded file.
 */
export function franchiseLogoUrl(code: string): string {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/team-logos/${code}.png`;
}
