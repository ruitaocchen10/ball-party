/** The reporting windows `ball_knower_leaderboard` and `my_ball_knower_standing` accept. */
export const LEADERBOARD_WINDOWS = ["week", "month", "year", "lifetime"] as const;
export type LeaderboardWindow = (typeof LEADERBOARD_WINDOWS)[number];

export const DEFAULT_LEADERBOARD_WINDOW: LeaderboardWindow = "week";

export const LEADERBOARD_WINDOW_COPY: Record<LeaderboardWindow, { label: string; caption: string }> = {
  week: { label: "Week", caption: "Last 7 days" },
  month: { label: "Month", caption: "Last 30 days" },
  year: { label: "Year", caption: "Last 365 days" },
  lifetime: { label: "All time", caption: "Every resolved pick" },
};

/** The `?window=` param: anything the RPC would reject falls back to the default. */
export function parseLeaderboardWindow(value: string | string[] | undefined): LeaderboardWindow {
  const first = Array.isArray(value) ? value[0] : value;
  return LEADERBOARD_WINDOWS.find((window) => window === first) ?? DEFAULT_LEADERBOARD_WINDOW;
}

/** Who the board ranks `me` against: everyone, or only accepted friends. */
export const LEADERBOARD_SCOPES = ["all", "friends"] as const;
export type LeaderboardScope = (typeof LEADERBOARD_SCOPES)[number];

export const DEFAULT_LEADERBOARD_SCOPE: LeaderboardScope = "all";

export const LEADERBOARD_SCOPE_LABEL: Record<LeaderboardScope, string> = {
  all: "Everyone",
  friends: "Friends",
};

/** The `?scope=` param: anything the RPC would reject falls back to the default. */
export function parseLeaderboardScope(value: string | string[] | undefined): LeaderboardScope {
  const first = Array.isArray(value) ? value[0] : value;
  return LEADERBOARD_SCOPES.find((scope) => scope === first) ?? DEFAULT_LEADERBOARD_SCOPE;
}

/** The board URL for a window and scope. Defaults are left out so shared links stay short. */
export function leaderboardHref(window: LeaderboardWindow, scope: LeaderboardScope): string {
  const params = new URLSearchParams();
  params.set("window", window);
  if (scope !== DEFAULT_LEADERBOARD_SCOPE) params.set("scope", scope);
  return `/leaderboard?${params.toString()}`;
}

/** "Top N%". Rounded up, so a player is never shown a better band than they hold. */
export function topPercent(rank: number, rankedCount: number): number | null {
  if (rankedCount <= 0) return null;
  return Math.ceil((rank * 100) / rankedCount);
}

export type Standing = {
  status: "ranked" | "unranked";
  rank: number | null;
  totalPoints: number;
  scoredPicks: number;
  rankedCount: number;
  minPicks: number;
};

/** What the caller's own row says, decided in one place so web states stay consistent. */
export function standingCopy(
  standing: Standing,
  scope: LeaderboardScope = DEFAULT_LEADERBOARD_SCOPE,
): { headline: string; detail: string } {
  if (standing.status === "unranked" || standing.rank === null) {
    const missing = Math.max(1, standing.minPicks - standing.scoredPicks);
    return {
      headline: "Not ranked yet",
      detail: `${missing} more scored ${missing === 1 ? "pick" : "picks"} to join the board`,
    };
  }
  if (scope === "friends") {
    return {
      headline: `#${standing.rank}`,
      detail: `Ranked ${standing.rank} of ${standing.rankedCount.toLocaleString("en-US")} on your friends board`,
    };
  }
  const band = topPercent(standing.rank, standing.rankedCount);
  return {
    headline: `#${standing.rank}`,
    detail: `Top ${band}% of ${standing.rankedCount.toLocaleString("en-US")} ranked players`,
  };
}
