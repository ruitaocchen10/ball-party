import { picksFromJson, type DraftPick } from "@/lib/games/qb-season-builder/board";
import { isObject, numbers } from "@/lib/games/qb-season-builder/json";

/**
 * A finished run's saved season, as `qb_season_builder.result` returns it.
 *
 * The jsonb arrives untyped, so this parses it once into something a screen can
 * draw without re-checking. It is only ever grades — the API never returns a
 * blended value, a source rating or the seed, so there is nothing here to strip. See
 * docs/games/qb_season_builder.md.
 */

export const AWARDS = ["mvp", "opoy", "all_pro", "pro_bowl", "sb_mvp"] as const;
export type Award = (typeof AWARDS)[number];

export const AWARD_LABELS: Record<Award, string> = {
  mvp: "MVP",
  opoy: "Offensive Player of the Year",
  all_pro: "First-Team All-Pro",
  pro_bowl: "Pro Bowl",
  sb_mvp: "Super Bowl MVP",
};

export const PLAYOFF_RESULTS = [
  "missed_playoffs",
  "lost_wild_card",
  "lost_divisional",
  "lost_conference",
  "lost_super_bowl",
  "won_super_bowl",
] as const;
export type PlayoffResult = (typeof PLAYOFF_RESULTS)[number];

export const PLAYOFF_LABELS: Record<PlayoffResult, string> = {
  missed_playoffs: "Missed the playoffs",
  lost_wild_card: "Lost in the wild card round",
  lost_divisional: "Lost in the divisional round",
  lost_conference: "Lost the conference championship",
  lost_super_bowl: "Lost the Super Bowl",
  won_super_bowl: "Won the Super Bowl",
};

export const SCORE_COMPONENT_LABELS: Record<string, string> = {
  stat_line: "Stat line",
  team_success: "Team success",
  awards: "Awards",
};

export type StatLine = {
  attempts: number;
  completions: number;
  passYards: number;
  passTds: number;
  interceptions: number;
  rating: number;
  rushYards: number;
  rushTds: number;
};

export type ScoreComponent = {
  component: string;
  /** Relative to the other components, not a percentage. */
  weight: number;
  /** 0-1: the share of real seasons this one beat. */
  percentile: number;
  /** What the component added to the score. They sum to it unless the 100 cap bit. */
  points: number;
};

export type SeasonResult = {
  matchId: string;
  mode: "visible" | "hidden";
  statLine: StatLine;
  record: { wins: number; losses: number };
  playoffs: { depth: number; result: PlayoffResult };
  awards: Record<Award, boolean>;
  score: number;
  breakdown: ScoreComponent[];
  picks: DraftPick[];
};

/** Where anyone can read a finished run's result, signed in or not. */
export function resultPath(matchId: string): string {
  return `/solo/qb-season-builder/result/${matchId}`;
}

/**
 * The result, or null when the row is not one a screen can draw. The caller
 * treats that as a result that is not there.
 */
export function resultFromJson(json: unknown): SeasonResult | null {
  if (!isObject(json) || typeof json.match_id !== "string") return null;
  if (json.mode !== "visible" && json.mode !== "hidden") return null;

  const stat = numbers(json.stat_line, [
    "attempts", "completions", "pass_yards", "pass_tds", "interceptions", "rating", "rush_yards", "rush_tds",
  ] as const);
  const record = numbers(json.record, ["wins", "losses"] as const);
  const playoffs = numbers(json.playoffs, ["depth"] as const);
  if (!stat || !record || !playoffs || typeof json.score !== "number") return null;
  if (!isObject(json.playoffs) || !(PLAYOFF_RESULTS as readonly unknown[]).includes(json.playoffs.result)) return null;

  if (!isObject(json.awards)) return null;
  const awards = {} as Record<Award, boolean>;
  for (const award of AWARDS) awards[award] = json.awards[award] === true;

  if (!Array.isArray(json.breakdown)) return null;
  const breakdown: ScoreComponent[] = [];
  for (const raw of json.breakdown) {
    const parts = numbers(raw, ["weight", "percentile", "points"] as const);
    if (!parts || !isObject(raw) || typeof raw.component !== "string") return null;
    breakdown.push({ component: raw.component, ...parts });
  }

  const picks = picksFromJson(json.picks);
  if (picks === null) return null;

  return {
    matchId: json.match_id,
    mode: json.mode,
    statLine: {
      attempts: stat.attempts,
      completions: stat.completions,
      passYards: stat.pass_yards,
      passTds: stat.pass_tds,
      interceptions: stat.interceptions,
      rating: stat.rating,
      rushYards: stat.rush_yards,
      rushTds: stat.rush_tds,
    },
    record,
    playoffs: { depth: playoffs.depth, result: json.playoffs.result as PlayoffResult },
    awards,
    score: json.score,
    breakdown,
    picks,
  };
}
