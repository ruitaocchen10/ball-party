import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import type { Database } from "@/lib/supabase/database.types";
import { fetchGameContexts, fetchNflSchedule, nflTeamFullName } from "./schedule";

type Row = Database["public"]["Tables"]["nfl_games"]["Row"];

function row(id: string, overrides: Partial<Row> = {}): Row {
  return {
    id,
    season: 2026,
    week: 1,
    kickoff: "2026-09-11T00:20:00+00:00",
    away_team: "KC",
    home_team: "BUF",
    stadium: "Highmark Stadium",
    primetime: true,
    updated_at: "2026-09-01T00:00:00+00:00",
    ...overrides,
  };
}

/**
 * A stand-in for the slice of the Supabase query builder these functions use.
 * `range` honours PostgREST's page cap, so a caller that forgets to page gets
 * back too few rows, as it would against the real API.
 */
function stubClient(table: Row[], { failFrom }: { failFrom?: number } = {}) {
  const requests: { range?: [number, number]; ids?: string[] } = {};
  const client = {
    from: vi.fn(() => ({
      select: (_columns: string, options?: { count?: string }) => {
        const query = {
          order: () => query,
          in: (_column: string, ids: string[]) => {
            requests.ids = ids;
            return Promise.resolve({ data: table.filter((game) => ids.includes(game.id)), error: null });
          },
          range: (from: number, to: number) => {
            requests.range = [from, to];
            if (failFrom !== undefined && from >= failFrom) return Promise.resolve({ data: null, error: { message: "boom" }, count: null });
            return Promise.resolve({ data: table.slice(from, Math.min(to + 1, from + 1000)), error: null, count: options?.count ? table.length : null });
          },
        };
        return query;
      },
    })),
  };
  return { client: client as unknown as SupabaseClient<Database>, spy: client.from, requests };
}

describe("nflTeamFullName", () => {
  it("expands team codes to their city and mascot for matchup copy", () => {
    expect(nflTeamFullName("CHI")).toBe("Chicago Bears");
    expect(nflTeamFullName("CAR")).toBe("Carolina Panthers");
  });
});

describe("fetchNflSchedule", () => {
  it("shapes rows into the composer's games, with a Z-form kickoff and a matchup label", async () => {
    const { client } = stubClient([row("2026_01_KC_BUF")]);

    expect(await fetchNflSchedule(client)).toEqual([{
      id: "2026_01_KC_BUF",
      season: 2026,
      week: 1,
      kickoff: "2026-09-11T00:20:00.000Z",
      away: "KC",
      home: "BUF",
      label: "Chiefs @ Bills",
      stadium: "Highmark Stadium",
      primetime: true,
    }]);
  });

  it("pages through a table larger than one response, keeping every row in order", async () => {
    const table = Array.from({ length: 2300 }, (_, index) => row(`game_${String(index).padStart(4, "0")}`));
    const { client } = stubClient(table);

    const games = await fetchNflSchedule(client);

    expect(games).toHaveLength(2300);
    expect(games.map((game) => game.id)).toEqual(table.map((game) => game.id));
  });

  it("returns an empty pool for an empty table", async () => {
    expect(await fetchNflSchedule(stubClient([]).client)).toEqual([]);
  });

  it("rejects when any page fails, rather than returning a schedule with a hole in it", async () => {
    const table = Array.from({ length: 2300 }, (_, index) => row(`game_${index}`));

    await expect(fetchNflSchedule(stubClient(table, { failFrom: 1000 }).client)).rejects.toThrow("NFL schedule is unavailable");
  });
});

describe("fetchGameContexts", () => {
  it("returns only the venue, kickoff and primetime flag of the games asked for", async () => {
    const { client } = stubClient([row("a"), row("b", { stadium: "Arrowhead", primetime: false }), row("c")]);

    expect(await fetchGameContexts(client, ["b"])).toEqual([
      { id: "b", stadium: "Arrowhead", kickoff: "2026-09-11T00:20:00.000Z", primetime: false },
    ]);
  });

  it("asks for each distinct game once", async () => {
    const { client, requests } = stubClient([row("a"), row("b")]);

    await fetchGameContexts(client, ["a", "b", "a", "b"]);

    expect(requests.ids).toEqual(["a", "b"]);
  });

  it("makes no request when no slot points at a game", async () => {
    const { client, spy } = stubClient([row("a")]);

    expect(await fetchGameContexts(client, [])).toEqual([]);
    expect(spy).not.toHaveBeenCalled();
  });
});
