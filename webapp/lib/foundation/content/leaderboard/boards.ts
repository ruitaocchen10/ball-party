import {
  DEFAULT_LEADERBOARD_SCOPE,
  topPercent,
  type LeaderboardScope,
  type LeaderboardWindow,
} from "@/lib/foundation/content/leaderboard/windows";

/** The boards under /leaderboard, in tab order. */
export const LEADERBOARD_BOARDS = ["ball-knower", "gamer"] as const;
export type LeaderboardBoard = (typeof LEADERBOARD_BOARDS)[number];

export const DEFAULT_LEADERBOARD_BOARD: LeaderboardBoard = "ball-knower";

export const LEADERBOARD_BOARD_COPY: Record<LeaderboardBoard, { label: string; title: string }> = {
  "ball-knower": { label: "Ball Knower", title: "Ball Knower" },
  gamer: { label: "Gamer", title: "Multiplayer wins" },
};

/** The `?board=` param: anything unknown falls back to the default. */
export function parseLeaderboardBoard(value: string | string[] | undefined): LeaderboardBoard {
  const first = Array.isArray(value) ? value[0] : value;
  return LEADERBOARD_BOARDS.find((board) => board === first) ?? DEFAULT_LEADERBOARD_BOARD;
}

/**
 * The solo games that keep an all-time best per player. Each one's board lives
 * with the game, at /solo/<slug>/leaderboard, not under /leaderboard.
 */
export const SOLO_BOARDS = ["higher-or-lower", "qb-season-builder"] as const;
export type SoloBoard = (typeof SOLO_BOARDS)[number];

export const SOLO_BOARD_COPY: Record<SoloBoard, { title: string; game: "higher_or_lower" | "qb_season_builder" }> = {
  "higher-or-lower": { title: "Higher or Lower", game: "higher_or_lower" },
  "qb-season-builder": { title: "QB Season Builder", game: "qb_season_builder" },
};

/** The slug as a SoloBoard, or null: used to send old /leaderboard?board=<solo game> links to the game's page. */
export function asSoloBoard(value: string | string[] | undefined): SoloBoard | null {
  const first = Array.isArray(value) ? value[0] : value;
  return SOLO_BOARDS.find((board) => board === first) ?? null;
}

/** QB Season Builder scores a visible run and a hidden run separately, so it has one board per mode. */
export const QB_MODES = ["visible", "hidden"] as const;
export type QbMode = (typeof QB_MODES)[number];

export const DEFAULT_QB_MODE: QbMode = "visible";

export const QB_MODE_LABEL: Record<QbMode, string> = { visible: "Visible", hidden: "Hidden" };

/** The `?mode=` param: anything unknown falls back to the default. */
export function parseQbMode(value: string | string[] | undefined): QbMode {
  const first = Array.isArray(value) ? value[0] : value;
  return QB_MODES.find((mode) => mode === first) ?? DEFAULT_QB_MODE;
}

/**
 * The URL for a /leaderboard board. Defaults (the Ball Knower board, the
 * everyone scope) are left out so shared links stay short. `window` only
 * applies to the boards that have windows.
 */
export function boardHref({
  board = DEFAULT_LEADERBOARD_BOARD,
  window,
  scope = DEFAULT_LEADERBOARD_SCOPE,
}: {
  board?: LeaderboardBoard;
  window?: LeaderboardWindow;
  scope?: LeaderboardScope;
}): string {
  const params = new URLSearchParams();
  if (board !== DEFAULT_LEADERBOARD_BOARD) params.set("board", board);
  if (window) params.set("window", window);
  if (scope !== DEFAULT_LEADERBOARD_SCOPE) params.set("scope", scope);
  const query = params.toString();
  return query ? `/leaderboard?${query}` : "/leaderboard";
}

/**
 * The URL for a solo game's board. The scope and the QB mode are left out at
 * their defaults, and `mode` only applies to QB Season Builder.
 */
export function soloBoardHref({
  board,
  scope = DEFAULT_LEADERBOARD_SCOPE,
  mode,
}: {
  board: SoloBoard;
  scope?: LeaderboardScope;
  mode?: QbMode;
}): string {
  const params = new URLSearchParams();
  if (scope !== DEFAULT_LEADERBOARD_SCOPE) params.set("scope", scope);
  if (board === "qb-season-builder" && mode && mode !== DEFAULT_QB_MODE) params.set("mode", mode);
  const query = params.toString();
  return `/solo/${board}/leaderboard${query ? `?${query}` : ""}`;
}

/** The caller's standing on the multiplayer wins board. */
export type GamerStanding = {
  status: "ranked" | "unranked";
  rank: number | null;
  wins: number;
  gamesPlayed: number;
  rankedCount: number;
  minWins: number;
};

/** The caller's standing on a solo board. `bestScore` is null until they have a recorded best. */
export type SoloStanding = {
  status: "ranked" | "unranked";
  rank: number | null;
  bestScore: number | null;
  rankedCount: number;
};

type StandingCopy = { headline: string; detail: string };

function rankedDetail(rank: number, rankedCount: number, scope: LeaderboardScope): string {
  const count = rankedCount.toLocaleString("en-US");
  if (scope === "friends") return `Ranked ${rank} of ${count} on your friends board`;
  return `Top ${topPercent(rank, rankedCount)}% of ${count} ranked players`;
}

export function gamerStandingCopy(standing: GamerStanding, scope: LeaderboardScope = DEFAULT_LEADERBOARD_SCOPE): StandingCopy {
  if (standing.status === "unranked" || standing.rank === null) {
    return { headline: "Not ranked yet", detail: "Win a multiplayer game in this window to join the board" };
  }
  return { headline: `#${standing.rank}`, detail: rankedDetail(standing.rank, standing.rankedCount, scope) };
}

export function soloStandingCopy(standing: SoloStanding, scope: LeaderboardScope = DEFAULT_LEADERBOARD_SCOPE): StandingCopy {
  if (standing.status === "unranked" || standing.rank === null) {
    return { headline: "Not ranked yet", detail: "Finish a solo run to put a score on this board" };
  }
  return { headline: `#${standing.rank}`, detail: rankedDetail(standing.rank, standing.rankedCount, scope) };
}

/** A solo score for display: a streak is a whole number, a QB score always keeps its one decimal (91.0, 80.5). */
export function formatSoloScore(score: number, board: SoloBoard): string {
  return board === "qb-season-builder"
    ? score.toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 })
    : score.toLocaleString("en-US");
}
