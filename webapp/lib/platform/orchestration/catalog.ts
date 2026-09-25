/**
 * The games, as the home screen advertises them.
 *
 * Hardcoded rather than read from Postgres because nothing about a game varies
 * per request, and a table would need a migration every time a copy line
 * changes. It moves to the database when games gain state the platform has to
 * read — availability by region, say, or per-player unlocks.
 *
 * `status` means playable, not planned. The auction, Higher or Lower, and
 * Sabotage Draft are built end to end; Wavelength is documented and unbuilt,
 * and saying otherwise on the home screen would be the product lying about
 * itself.
 */
export type GameStatus = "live" | "development";

/** One choice offered when a solo run starts — see `Game.soloModes`. */
export type SoloMode = { value: string; label: string; description: string };

export type Game = {
  slug: string;
  /**
   * The `matches.game` a tile starts, or null when nothing can start it yet.
   *
   * `status` is what the home screen may advertise; this is the stricter
   * promise, that a run dispatcher and a setup RPC exist behind the tile. The
   * two run in opposite directions while a game is being built in slices, so
   * they are separate fields — and this is the only place the catalogue's slug
   * and the durable record's name are tied together.
   */
  match: MatchGame | null;
  /** Split across lines the way it should wrap on a card. */
  name: readonly string[];
  /**
   * For surfaces too narrow for `name` — the hero fan, where each card is
   * mostly covered by the next one. Kept here rather than truncated at the
   * call site so the shortening is a decision someone made, not an accident
   * of CSS.
   */
  shortName: readonly string[];
  /** The kicker above the name — what kind of game this is. */
  kind: string;
  tagline: string;
  players: string;
  status: GameStatus;
  /** Whether one person alone gets anything out of it. */
  solo: boolean;
  /**
   * Whether a room can start it. False for a game that only exists as a solo
   * run — it has no lobby to open, so it stays out of the room grid, the
   * host's picker and `startableGames()`.
   */
  group: boolean;
  /**
   * The choices a solo run makes at start, first one the default. Sent with
   * the Play solo form as `mode`; a start with none sent gets the game's own
   * default. Surfaces that start a run in one tap (the sidebar) send the player
   * to the Solo games page for a game that has any, so the choice is never
   * skipped. Absent when a game has nothing to choose.
   */
  soloModes?: readonly SoloMode[];
  /**
   * A second, independent choice a solo run makes at start, sent as `era`.
   * Same shape and same rule as `soloModes` — first is the default, absent
   * when a game has nothing to choose — just a second axis rather than a
   * combined one, since the two vary independently (QB Season Builder's era
   * narrows the pool a spin draws from; it does not touch what a spin reveals).
   */
  soloEras?: readonly SoloMode[];
  /**
   * The one game the home grid gives a double-width tile to. Exactly one live
   * game should carry it — the grid places it explicitly and lets the rest
   * flow around it, so two would collide.
   */
  featured: boolean;
};

/**
 * The values persisted by `matches.game`. They predate the public catalog's
 * URL slugs, so this is the one translation point for durable game records.
 */
export const MATCH_GAME_NAMES = {
  auction_team_builder: "Auction Team Builder",
  cards_against_humanity: "Cards Against Humanity",
  higher_or_lower: "Higher or Lower",
  wavelength_2v2: "2v2 Wavelength",
  sabotage_draft: "Sabotage Draft",
  qb_season_builder: "QB Season Builder",
} as const;

export type MatchGame = keyof typeof MATCH_GAME_NAMES;

export function matchGameName(game: MatchGame): string {
  return MATCH_GAME_NAMES[game];
}

/** The games a room can offer at all, live or not — the one place `group` is read. */
export function groupGames(): Game[] {
  return GAMES.filter((game) => game.group);
}

/** The games a room can actually start today, by their durable record name. */
export function startableGames(): MatchGame[] {
  return groupGames().map((game) => game.match).filter((game) => game !== null);
}

/** The games a lone player can actually start today, by their durable record name. */
export function soloGames(): MatchGame[] {
  return GAMES.filter((game) => game.solo).map((game) => game.match).filter((game) => game !== null);
}

export const GAMES: readonly Game[] = [
  {
    slug: "sabotage-draft",
    match: "sabotage_draft",
    name: ["Sabotage", "draft"],
    shortName: ["Sabotage", "draft"],
    kind: "Group · hidden picks",
    tagline: "Spin your own team history, then try to wreck everyone else’s pick.",
    players: "2–4 players",
    status: "live",
    solo: false,
    group: true,
    featured: false,
  },
  {
    slug: "qb-season-builder",
    match: "qb_season_builder",
    name: ["QB season", "builder"],
    shortName: ["QB season", "builder"],
    kind: "Solo · draft",
    tagline: "Spin a team-season six times and build one quarterback from the best trait on offer.",
    players: "1 player",
    status: "live",
    solo: true,
    group: false,
    soloModes: [
      { value: "visible", label: "Visible", description: "Letter grades show while you pick." },
      { value: "hidden", label: "Hidden", description: "No grades until the run is over. Pick on what you know." },
    ],
    soloEras: [
      { value: "all", label: "All Years", description: "Every team-season, 2006-2025." },
      { value: "classic", label: "Classic", description: "2006-2015." },
      { value: "modern", label: "Modern", description: "2016-2025." },
    ],
    featured: false,
  },
  {
    slug: "higher-or-lower",
    match: "higher_or_lower",
    name: ["Higher", "or lower"],
    shortName: ["Higher", "or lower"],
    kind: "Group · simultaneous",
    tagline: "Everyone calls higher or lower at once. Longest streak wins.",
    players: "2–4 players",
    status: "live",
    solo: true,
    group: true,
    featured: false,
  },
  {
    slug: "auction-team-builder",
    match: "auction_team_builder",
    name: ["Auction", "team builder"],
    shortName: ["Auction"],
    kind: "Group · hidden points",
    tagline: "Bid on mystery player-weeks. Fantasy points stay hidden until the bidding closes.",
    players: "2–4 players",
    status: "live",
    solo: false,
    group: true,
    featured: true,
  },
  {
    slug: "wavelength",
    match: null,
    name: ["2v2", "Wavelength"],
    shortName: ["2v2", "Wavelength"],
    kind: "2v2 · hidden target",
    tagline: "One clue, one dial, one partner who carves up a fuzzy scale differently than you do.",
    players: "4 players",
    status: "development",
    solo: false,
    group: true,
    featured: false,
  },
] as const;
