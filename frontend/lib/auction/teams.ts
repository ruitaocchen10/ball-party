/**
 * Auction lots retain nflverse's familiar broadcast abbreviations, while the
 * shared logo bucket is keyed by Pro Football Reference franchise codes. The
 * auction pool also preserves the period-correct STL, SD, and OAK labels, so
 * those need to resolve to the same franchise asset as their current name.
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
export function auctionLogoCode(team: string): string | null {
  return LOGO_CODE[team.toUpperCase()] ?? null;
}
