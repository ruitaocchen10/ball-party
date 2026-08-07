/**
 * The games, as the home screen advertises them.
 *
 * Hardcoded rather than read from Postgres because nothing about a game varies
 * per request, and a table would need a migration every time a copy line
 * changes. It moves to the database when games gain state the platform has to
 * read — availability by region, say, or per-player unlocks.
 *
 * TODO: `status` is a display placeholder. No game is implemented yet, so
 * "live" here means "documented and next up", not "playable". Flip these to the
 * truth as each game ships.
 */
export type GameStatus = "live" | "development";

export type Game = {
  slug: string;
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
  duration: string;
  status: GameStatus;
  /** Whether one person alone gets anything out of it. */
  solo: boolean;
  /**
   * The one game the home grid gives a double-width tile to. Exactly one live
   * game should carry it — the grid places it explicitly and lets the rest
   * flow around it, so two would collide.
   */
  featured: boolean;
};

export const GAMES: readonly Game[] = [
  {
    slug: "higher-or-lower",
    name: ["Higher", "or lower"],
    shortName: ["Higher", "or lower"],
    kind: "Solo or group",
    tagline: "Two stat lines, one call. Keep the streak alive or hand it over.",
    players: "1–4 players",
    duration: "3–6 min",
    status: "live",
    solo: true,
    featured: false,
  },
  {
    slug: "auction-team-builder",
    name: ["Auction", "team builder"],
    shortName: ["Auction"],
    kind: "Group · hidden points",
    tagline: "Bid on mystery player-weeks. Fantasy points stay hidden until the bidding closes.",
    players: "4 players",
    duration: "10–14 min",
    status: "live",
    solo: false,
    featured: true,
  },
  {
    slug: "wavelength",
    name: ["2v2", "Wavelength"],
    shortName: ["2v2", "Wavelength"],
    kind: "2v2 · hidden target",
    tagline: "One clue, one dial, one partner who carves up a fuzzy scale differently than you do.",
    players: "4 players",
    duration: "8–12 min",
    status: "live",
    solo: false,
    featured: false,
  },
  {
    slug: "in-development",
    name: ["In", "development"],
    shortName: ["In dev"],
    kind: "",
    tagline: "",
    players: "Coming soon",
    duration: "",
    status: "development",
    solo: false,
    featured: false,
  },
] as const;
