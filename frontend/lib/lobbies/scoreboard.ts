import type { createClient } from "@/lib/supabase/server";

/**
 * Wins this room's members have picked up, for as long as the room has been
 * open — not a persisted stat, just a read over the room's own history.
 *
 * Every game already writes one game-agnostic fact per finished match:
 * `match_players.placement`, ranked by `private.finish_match` (0009) the same
 * way `FinalStandingsRow.rank` assumes it — row 1 is the winner, whatever the
 * game. Counting `placement = 1` across a lobby's matches is therefore a read,
 * not a new concept: nothing here decides what a "win" means a second time.
 *
 * Scoped to the lobby's own lifetime rather than persisted, so it resets when
 * the room closes — this is the session's bragging rights, not a lifetime
 * record. RLS already allows it: `match_players_select_member` (0009) reads
 * through `is_run_member`, which passes for any *current* lobby member on any
 * run that ever belonged to this room, closed or not.
 */
export type WinRow = { user_id: string };

/** Pure so it can be tested without a database: user_id → win count. */
export function tallyWins(rows: WinRow[]): Map<string, number> {
  const wins = new Map<string, number>();
  for (const row of rows) {
    wins.set(row.user_id, (wins.get(row.user_id) ?? 0) + 1);
  }
  return wins;
}

export async function fetchLobbyWins(
  supabase: Awaited<ReturnType<typeof createClient>>,
  lobbyId: string,
): Promise<Map<string, number>> {
  const { data } = await supabase
    .from("match_players")
    .select("user_id, matches!inner(status, runs!inner(lobby_id))")
    .eq("placement", 1)
    .eq("matches.status", "complete")
    .eq("matches.runs.lobby_id", lobbyId);

  return tallyWins(data ?? []);
}
