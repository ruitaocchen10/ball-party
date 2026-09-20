import type { Player } from "@/lib/foundation/content/prompts/types";

const PLAYERS_URL = "https://github.com/nflverse/nflverse-data/releases/download/players/players.csv";

function parseCsvRow(row: string): string[] {
  const values: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < row.length; index += 1) {
    const character = row[index];
    if (character === '"') {
      if (quoted && row[index + 1] === '"') { value += '"'; index += 1; }
      else quoted = !quoted;
    } else if (character === "," && !quoted) {
      values.push(value);
      value = "";
    } else value += character;
  }
  values.push(value);
  return values;
}

/** Converts nflverse's active-player release into the composer’s safe card shape. */
export function parseNflPlayers(csv: string): Player[] {
  const [header, ...rows] = csv.trim().split(/\r?\n/);
  if (!header) return [];
  const columns = new Map(parseCsvRow(header).map((name, index) => [name, index]));
  const read = (values: string[], name: string) => values[columns.get(name) ?? -1] ?? "";

  return rows.flatMap((row) => {
    const values = parseCsvRow(row);
    const id = read(values, "gsis_id");
    const name = read(values, "display_name");
    const position = read(values, "position");
    const team = read(values, "latest_team");
    if (read(values, "status") !== "ACT" || !id || !name || !team || !position) return [];
    return [{ id, name, position, team, headshotUrl: read(values, "headshot") }];
  }).sort((left, right) => left.position.localeCompare(right.position) || left.name.localeCompare(right.name));
}

/** Current NFL players, cached on the server for one hour like the schedule. */
export async function fetchNflPlayers(): Promise<Player[]> {
  const response = await fetch(PLAYERS_URL, { next: { revalidate: 3600 } });
  if (!response.ok) throw new Error("NFL players are unavailable");
  return parseNflPlayers(await response.text());
}
