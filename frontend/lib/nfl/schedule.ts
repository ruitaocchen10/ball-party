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
  LA: "Rams", LAC: "Chargers", LV: "Raiders", MIA: "Dolphins", MIN: "Vikings", NE: "Patriots", NO: "Saints", NYG: "Giants",
  NYJ: "Jets", PHI: "Eagles", PIT: "Steelers", SEA: "Seahawks", SF: "49ers", TB: "Buccaneers", TEN: "Titans", WAS: "Commanders",
};

const TEAM_FULL_NAMES: Record<string, string> = {
  ARI: "Arizona Cardinals", ATL: "Atlanta Falcons", BAL: "Baltimore Ravens", BUF: "Buffalo Bills", CAR: "Carolina Panthers", CHI: "Chicago Bears", CIN: "Cincinnati Bengals", CLE: "Cleveland Browns",
  DAL: "Dallas Cowboys", DEN: "Denver Broncos", DET: "Detroit Lions", GB: "Green Bay Packers", HOU: "Houston Texans", IND: "Indianapolis Colts", JAX: "Jacksonville Jaguars", KC: "Kansas City Chiefs",
  LA: "Los Angeles Rams", LAC: "Los Angeles Chargers", LV: "Las Vegas Raiders", MIA: "Miami Dolphins", MIN: "Minnesota Vikings", NE: "New England Patriots", NO: "New Orleans Saints", NYG: "New York Giants",
  NYJ: "New York Jets", PHI: "Philadelphia Eagles", PIT: "Pittsburgh Steelers", SEA: "Seattle Seahawks", SF: "San Francisco 49ers", TB: "Tampa Bay Buccaneers", TEN: "Tennessee Titans", WAS: "Washington Commanders",
};

const EASTERN_TIME_ZONE = "America/New_York";
const easternTimeFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: EASTERN_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});

export function nflTeamName(code: string): string {
  return TEAM_NAMES[code] ?? code;
}

/** Full city-and-mascot name for prose such as a matchup line. */
export function nflTeamFullName(code: string): string {
  return TEAM_FULL_NAMES[code] ?? nflTeamName(code);
}

/**
 * The schedule feed has a kickoff but no durable broadcast-window field.
 * Keep the user-facing distinction deliberately broad: the national evening
 * Thursday, Sunday, and Monday windows are all simply "Primetime".
 */
export function isPrimetimeKickoff(kickoff: string): boolean {
  const date = new Date(kickoff);
  if (Number.isNaN(date.getTime())) return false;
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: EASTERN_TIME_ZONE,
      weekday: "short",
      hour: "numeric",
      hourCycle: "h23",
    }).formatToParts(date).filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
  );
  const weekday = parts.weekday;
  const hour = Number(parts.hour);
  return (weekday === "Thu" || weekday === "Sun" || weekday === "Mon") && hour >= 19;
}

/**
 * nflverse's `gameday` and `gametime` fields are a wall-clock time in
 * Eastern Time, rather than a UTC timestamp. Convert that local time into a
 * real instant before handing it to browser-local formatting.
 */
function easternTimeToIso(gameday: string, gametime: string): string {
  const localAsUtc = new Date(`${gameday}T${gametime}Z`);
  if (Number.isNaN(localAsUtc.getTime())) return "";

  const parts = Object.fromEntries(
    easternTimeFormatter
      .formatToParts(localAsUtc)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  const easternClockAsUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  const easternOffset = easternClockAsUtc - localAsUtc.getTime();

  return new Date(localAsUtc.getTime() - easternOffset).toISOString();
}

function parseCsvRow(row: string): string[] {
  const values: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < row.length; index += 1) {
    const character = row[index];
    if (character === '"') {
      if (quoted && row[index + 1] === '"') {
        value += '"';
        index += 1;
      } else quoted = !quoted;
    } else if (character === "," && !quoted) {
      values.push(value);
      value = "";
    } else value += character;
  }
  values.push(value);
  return values;
}

/** Shapes nflverse's released schedule into the small, public composer pool. */
export function parseNflSchedule(csv: string): NflScheduleGame[] {
  const [header, ...rows] = csv.trim().split(/\r?\n/);
  if (!header) return [];
  const columns = new Map(parseCsvRow(header).map((name, index) => [name, index]));
  const read = (values: string[], name: string) => values[columns.get(name) ?? -1] ?? "";

  return rows.flatMap((row) => {
    const values = parseCsvRow(row);
    const season = Number(read(values, "season"));
    const week = Number(read(values, "week"));
    const gameType = read(values, "game_type");
    const gameId = read(values, "game_id");
    const away = read(values, "away_team");
    const home = read(values, "home_team");
    const gameday = read(values, "gameday");
    const gametime = read(values, "gametime");
    const stadium = read(values, "stadium");
    const kickoff = gameday && gametime ? easternTimeToIso(gameday, gametime) : "";
    if (gameType !== "REG" || !gameId || !away || !home || !Number.isInteger(season) || !Number.isInteger(week) || !kickoff) return [];
    return [{
      id: gameId,
      season,
      week,
      kickoff,
      away,
      home,
      label: `${nflTeamName(away)} @ ${nflTeamName(home)}`,
      stadium,
      primetime: isPrimetimeKickoff(kickoff),
    }];
  }).sort((left, right) => left.kickoff.localeCompare(right.kickoff));
}

export async function fetchNflSchedule(): Promise<NflScheduleGame[]> {
  const response = await fetch("https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv", {
    next: { revalidate: 3600 },
  });
  if (!response.ok) throw new Error("NFL schedule is unavailable");
  return parseNflSchedule(await response.text());
}
