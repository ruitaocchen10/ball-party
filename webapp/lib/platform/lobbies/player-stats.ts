import { summarizeProfile, type CompletedMatch, type ProfileSummary } from "@/lib/foundation/identity/summary";
import type { MatchGame } from "@/lib/platform/orchestration/catalog";
import type { createClient } from "@/lib/supabase/server";

/**
 * Each seated member's career record — win rate, best streak, recent form —
 * next to the room. `lib/lobbies/scoreboard.ts` already shows *this session's*
 * wins; this is the thing that's missing next to it, what someone brings into
 * the room rather than what they've done since sitting down.
 *
 * `summarizeProfile` (lib/profile/summary.ts) already turns a player's
 * completed matches into these facts for the profile page — reused as-is
 * here, just run once per seated member instead of once for the viewer.
 *
 * The RLS a lobby member already has (`match_players_select_member`,
 * `matches_select_member` — see 0004) only covers matches from runs of *this*
 * lobby, the same way `fetchLobbyWins` works. A co-player's full career
 * — matches from other lobbies they were in — needs the
 * `lobby_member_match_history` RPC (0080), which is scoped the same way:
 * readable only by someone who is *currently* a member of this lobby, for
 * people who are *currently* members of this lobby.
 *
 * Refreshes for free on `LobbyRealtime`'s existing `matches` subscription
 * (unfiltered — RLS scopes what arrives) whenever a match finishes inside
 * *this* lobby. A co-player's match finishing in a different, concurrent
 * lobby doesn't reach this lobby's channel, so their stats here can lag
 * until this room's own next refresh — acceptable for a waiting-room glance,
 * not a source of truth the way the profile page is.
 */
// Every field is nullable in the generated type — Postgres composite types
// carry that possibility regardless of what the query behind them actually
// produces (see 0080's `match_history_row`) — so this mirrors the same
// nullability rather than asserting it away.
export type MatchHistoryRow = {
  user_id: string | null;
  match_id: string | null;
  game: string | null;
  ended_at: string | null;
  placement: number | null;
  raw_score: number | null;
};

/** Pure so it can be tested without a database, same pattern as tallyWins. */
export function groupMatchHistoryByUser(rows: MatchHistoryRow[]): Map<string, CompletedMatch[]> {
  const byUser = new Map<string, CompletedMatch[]>();
  for (const row of rows) {
    if (!row.user_id || !row.match_id || !row.game || !row.ended_at) continue;
    const list = byUser.get(row.user_id) ?? [];
    list.push({
      id: row.match_id,
      game: row.game as MatchGame,
      endedAt: row.ended_at,
      placement: row.placement,
      rawScore: row.raw_score,
    });
    byUser.set(row.user_id, list);
  }
  return byUser;
}

export async function fetchLobbyMemberStats(
  supabase: Awaited<ReturnType<typeof createClient>>,
  lobbyId: string,
): Promise<Map<string, ProfileSummary>> {
  const { data } = await supabase.rpc("lobby_member_match_history", { p_lobby_id: lobbyId });
  const byUser = groupMatchHistoryByUser(data ?? []);
  return new Map([...byUser].map(([userId, matches]) => [userId, summarizeProfile(matches)]));
}
