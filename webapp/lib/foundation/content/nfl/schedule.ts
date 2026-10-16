import type { SupabaseClient } from "@supabase/supabase-js";

import type { Database } from "@/lib/supabase/database.types";

/**
 * The regular-season schedule, read from `public.nfl_games` (migration 0119).
 * The iOS app reads the same table, so a matchup shows the same venue, kickoff
 * and Primetime flag on both. The database fills it from nflverse's games.csv
 * (`prompts_private.sync_nfl_games`) and owns the Eastern-time conversion and
 * the primetime rule, so nothing here fetches or parses the feed.
 */
export type NflScheduleGame = {
  id: string;
  season: number;
  week: number;
  kickoff: string;
  away: string;
  home: string;
  label: string;
  /** Official venue from the schedule feed; important for neutral-site games. */
  stadium: string;
  /** Thursday, Sunday, and Monday national evening windows. */
  primetime: boolean;
};

const TEAM_NAMES: Record<string, string> = {
  ARI: "Cardinals", ATL: "Falcons", BAL: "Ravens", BUF: "Bills", CAR: "Panthers", CHI: "Bears", CIN: "Bengals", CLE: "Browns",
  DAL: "Cowboys", DEN: "Broncos", DET: "Lions", GB: "Packers", HOU: "Texans", IND: "Colts", JAX: "Jaguars", KC: "Chiefs",
  LAC: "Chargers", LAR: "Rams", LV: "Raiders", MIA: "Dolphins", MIN: "Vikings", NE: "Patriots", NO: "Saints", NYG: "Giants",
  NYJ: "Jets", PHI: "Eagles", PIT: "Steelers", SEA: "Seahawks", SF: "49ers", TB: "Buccaneers", TEN: "Titans", WAS: "Commanders",
};

const TEAM_FULL_NAMES: Record<string, string> = {
  ARI: "Arizona Cardinals", ATL: "Atlanta Falcons", BAL: "Baltimore Ravens", BUF: "Buffalo Bills", CAR: "Carolina Panthers", CHI: "Chicago Bears", CIN: "Cincinnati Bengals", CLE: "Cleveland Browns",
  DAL: "Dallas Cowboys", DEN: "Denver Broncos", DET: "Detroit Lions", GB: "Green Bay Packers", HOU: "Houston Texans", IND: "Indianapolis Colts", JAX: "Jacksonville Jaguars", KC: "Kansas City Chiefs",
  LAC: "Los Angeles Chargers", LAR: "Los Angeles Rams", LV: "Las Vegas Raiders", MIA: "Miami Dolphins", MIN: "Minnesota Vikings", NE: "New England Patriots", NO: "New Orleans Saints", NYG: "New York Giants",
  NYJ: "New York Jets", PHI: "Philadelphia Eagles", PIT: "Pittsburgh Steelers", SEA: "Seattle Seahawks", SF: "San Francisco 49ers", TB: "Tampa Bay Buccaneers", TEN: "Tennessee Titans", WAS: "Washington Commanders",
};

export function nflTeamName(code: string): string {
  return TEAM_NAMES[code] ?? code;
}

/** Full city-and-mascot name for prose such as a matchup line. */
export function nflTeamFullName(code: string): string {
  return TEAM_FULL_NAMES[code] ?? nflTeamName(code);
}

type NflGameRow = Database["public"]["Tables"]["nfl_games"]["Row"];

/** What a matchup cover needs from a game, keyed by the game id a slot carries as `sourceGameId`. */
export type NflGameContext = Pick<NflScheduleGame, "id" | "stadium" | "kickoff" | "primetime">;

// PostgREST's default page size (`max_rows`); a larger request is silently cut short.
const PAGE_SIZE = 1000;

/** PostgREST prints "+00:00"; consumers expect the `Z` form `toISOString` gives. */
function toIso(timestamp: string): string {
  return new Date(timestamp).toISOString();
}

function toScheduleGame(row: NflGameRow): NflScheduleGame {
  return {
    id: row.id,
    season: row.season,
    week: row.week,
    kickoff: toIso(row.kickoff),
    away: row.away_team,
    home: row.home_team,
    label: `${nflTeamName(row.away_team)} @ ${nflTeamName(row.home_team)}`,
    stadium: row.stadium,
    primetime: row.primetime,
  };
}

/**
 * Every regular-season game the database knows, earliest kickoff first — the
 * admin composer's pool, which spans past seasons. Paged, because the table
 * holds more rows than one PostgREST response returns.
 */
export async function fetchNflSchedule(supabase: SupabaseClient<Database>): Promise<NflScheduleGame[]> {
  const page = (from: number) =>
    supabase.from("nfl_games").select("*", from === 0 ? { count: "exact" } : undefined)
      .order("kickoff").order("id").range(from, from + PAGE_SIZE - 1);

  const first = await page(0);
  if (first.error) throw new Error("NFL schedule is unavailable");
  const rest = Math.ceil(((first.count ?? 0) - PAGE_SIZE) / PAGE_SIZE);
  const others = await Promise.all(Array.from({ length: Math.max(rest, 0) }, (_, index) => page((index + 1) * PAGE_SIZE)));
  const failed = others.find((result) => result.error);
  if (failed) throw new Error("NFL schedule is unavailable");

  return [first, ...others].flatMap((result) => result.data ?? []).map(toScheduleGame);
}

/**
 * The few games a feed's slots point at. The feed only ever needs the games its
 * own posts are about, so it asks for those rather than the whole table.
 */
export async function fetchGameContexts(supabase: SupabaseClient<Database>, gameIds: string[]): Promise<NflGameContext[]> {
  const ids = [...new Set(gameIds)];
  if (ids.length === 0) return [];
  const { data, error } = await supabase.from("nfl_games").select("id, stadium, kickoff, primetime").in("id", ids);
  if (error) throw new Error("NFL schedule is unavailable");
  return data.map(({ id, stadium, kickoff, primetime }) => ({ id, stadium, kickoff: toIso(kickoff), primetime }));
}

/**
 * The games a Bold Predictions post can still be about: the games of the week
 * whose first kickoff follows the post's lock time, from that lock on. The
 * week is decided as prompts_private.bold_prediction_week does (0171), and a
 * matchup tag is only valid for a game that has not kicked off at the lock
 * (0217), which is what validates a matchup tag on write. The post locks at
 * the week's first Sunday kickoff, so the Thursday game is not among them.
 * Empty once the schedule has nothing after the lock.
 */
export async function fetchWeekAfter(supabase: SupabaseClient<Database>, lockAt: string): Promise<NflScheduleGame[]> {
  const first = await supabase.from("nfl_games").select("season, week").gte("kickoff", lockAt).order("kickoff").limit(1).maybeSingle();
  if (first.error) throw new Error("NFL schedule is unavailable");
  if (!first.data) return [];
  const { data, error } = await supabase
    .from("nfl_games").select("*").eq("season", first.data.season).eq("week", first.data.week).gte("kickoff", lockAt).order("kickoff").order("id");
  if (error) throw new Error("NFL schedule is unavailable");
  return data.map(toScheduleGame);
}
