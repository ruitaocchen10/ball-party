import { matchGameName, type MatchGame } from "@/lib/platform/orchestration/catalog";
import type { createClient } from "@/lib/supabase/server";

export type RoomActivity = {
  id: string;
  game: MatchGame;
  endedAt: string;
  winnerName: string;
};

type CompletedMatchRow = {
  id: string;
  game: string;
  ended_at: string | null;
};

type WinnerRow = {
  match_id: string;
  user_id: string;
};

/**
 * Turns the lobby's completed matches into its small, durable activity feed.
 * A match and its winner are separate platform records, so keeping the join
 * here makes the presentation component a simple read of room events.
 */
export function buildRoomActivity(
  matches: CompletedMatchRow[],
  winners: WinnerRow[],
  namesByUser: Map<string, string>,
): RoomActivity[] {
  const winnerByMatch = new Map(winners.map((winner) => [winner.match_id, namesByUser.get(winner.user_id) ?? "A player"]));

  return matches.flatMap((match) => {
    if (!match.ended_at) return [];
    return [{
      id: match.id,
      game: match.game as MatchGame,
      endedAt: match.ended_at,
      winnerName: winnerByMatch.get(match.id) ?? "A player",
    }];
  });
}

export async function fetchLobbyActivity(
  supabase: Awaited<ReturnType<typeof createClient>>,
  lobbyId: string,
): Promise<RoomActivity[]> {
  const { data: matches } = await supabase
    .from("matches")
    .select("id, game, ended_at, runs!inner(lobby_id)")
    .eq("status", "complete")
    .eq("runs.lobby_id", lobbyId)
    .order("ended_at", { ascending: false })
    .limit(5);

  const completed = (matches ?? []) as CompletedMatchRow[];
  if (completed.length === 0) return [];

  const { data: winners } = await supabase
    .from("match_players")
    .select("match_id, user_id")
    .in("match_id", completed.map((match) => match.id))
    .eq("placement", 1);

  const winnerRows = (winners ?? []) as WinnerRow[];
  const winnerIds = [...new Set(winnerRows.map((winner) => winner.user_id))];
  const { data: profiles } = winnerIds.length
    ? await supabase.from("profiles").select("id, display_name").in("id", winnerIds)
    : { data: [] };
  const namesByUser = new Map((profiles ?? []).map((profile) => [profile.id, profile.display_name]));

  return buildRoomActivity(completed, winnerRows, namesByUser);
}

/** Small, stable relative-time label for a waiting-room glance. */
export function timeAgo(endedAt: string, now = new Date()): string {
  const seconds = Math.max(0, Math.floor((now.getTime() - new Date(endedAt).getTime()) / 1_000));
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function activityLabel(activity: RoomActivity): string {
  return `${activity.winnerName} won ${matchGameName(activity.game)}`;
}
