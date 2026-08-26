/**
 * Pro Football Reference's own 3-letter franchise codes, mapped to each
 * franchise's current name. `sabotage_draft_round_spins.franchise_code` (and,
 * before it, the shared `sabotage_draft_rounds.franchise_code`) stores this
 * code because it stays stable across a franchise's entire history — PFR
 * unifies every relocation and rename under one code (see
 * docs/games/sabotage_draft_data_scoping.md §2: `oti` spans the Houston
 * Oilers through the Tennessee Titans, `crd` spans the Chicago through
 * Arizona Cardinals, and so on). That stability is exactly why several of
 * these codes don't read as the modern team name on sight — `clt` (Colts),
 * `crd` (Cardinals), `htx` (Texans), `oti` (Oilers/Titans), `rav` (Ravens),
 * and `sdg` (Chargers) are the ones most likely to need this lookup.
 *
 * Display only: nothing server-side reads names, only codes, so this map has
 * no bearing on picks, guesses, or scoring — it exists purely so a player
 * sees "Tennessee Titans" instead of "oti".
 */
export const FRANCHISE_NAMES: Record<string, string> = {
  atl: "Atlanta Falcons",
  buf: "Buffalo Bills",
  car: "Carolina Panthers",
  chi: "Chicago Bears",
  cin: "Cincinnati Bengals",
  cle: "Cleveland Browns",
  clt: "Indianapolis Colts",
  crd: "Arizona Cardinals",
  dal: "Dallas Cowboys",
  den: "Denver Broncos",
  det: "Detroit Lions",
  gnb: "Green Bay Packers",
  htx: "Houston Texans",
  jax: "Jacksonville Jaguars",
  kan: "Kansas City Chiefs",
  mia: "Miami Dolphins",
  min: "Minnesota Vikings",
  nor: "New Orleans Saints",
  nwe: "New England Patriots",
  nyg: "New York Giants",
  nyj: "New York Jets",
  oti: "Tennessee Titans",
  phi: "Philadelphia Eagles",
  pit: "Pittsburgh Steelers",
  rai: "Las Vegas Raiders",
  ram: "Los Angeles Rams",
  rav: "Baltimore Ravens",
  sdg: "Los Angeles Chargers",
  sea: "Seattle Seahawks",
  sfo: "San Francisco 49ers",
  tam: "Tampa Bay Buccaneers",
  was: "Washington Commanders",
};

/** Falls back to the raw code so an unmapped future entry never disappears. */
export function franchiseName(code: string): string {
  return FRANCHISE_NAMES[code] ?? code;
}
