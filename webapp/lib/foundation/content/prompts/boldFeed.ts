import { fetchWeekAfter } from "@/lib/foundation/content/nfl/schedule";
import { toBoldPrediction, type BoldPredictionBoardData } from "@/lib/foundation/content/prompts/boldPredictions";
import type { PlayerResult } from "@/lib/foundation/content/prompts/players";
import type { Post } from "@/lib/foundation/content/prompts/types";
import type { createClient } from "@/lib/supabase/server";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * Everything the Bold Predictions board renders on the detail page.
 *
 * `bold_predictions_for_post` is the only sanctioned read of other people's
 * rows: before lock it returns just the viewer's own, after lock everyone's
 * (0171), so this never has to decide who may see what. The week's games and
 * the tagged players are public reference data, looked up so a tag can be drawn
 * as art and a name instead of an id.
 */
export async function fetchBoldPredictionBoard(
  supabase: SupabaseServerClient,
  post: Pick<Post, "id" | "lockAt">,
  viewerId: string | null,
): Promise<BoldPredictionBoardData> {
  const [{ data: rows }, weekGames] = await Promise.all([
    supabase.schema("prompts").rpc("bold_predictions_for_post", { p_post_id: post.id }),
    fetchWeekAfter(supabase, post.lockAt).catch(() => []),
  ]);
  const predictionRows = rows ?? [];

  const authorIds = [...new Set(predictionRows.map((row) => row.author_id))];
  const playerIds = [...new Set(predictionRows.filter((row) => row.target_type === "player").map((row) => row.target_id))];
  const [profiles, playerRows] = await Promise.all([
    authorIds.length ? supabase.from("profiles").select("id, display_name, username").in("id", authorIds).then((r) => r.data ?? []) : [],
    playerIds.length ? supabase.schema("prompts").rpc("players_by_ids", { p_ids: playerIds }).then((r) => r.data ?? []) : [],
  ]);
  const nameById = new Map(profiles.map((profile) => [profile.id, profile.display_name]));
  const usernameById = new Map(profiles.map((profile) => [profile.id, profile.username]));

  const players: Record<string, PlayerResult> = {};
  for (const row of playerRows) {
    players[row.player_id] = {
      id: row.player_id, name: row.display_name, position: row.position, team: row.team, headshotUrl: row.headshot_url, status: row.status,
    };
  }

  return { predictions: predictionRows.map((row) => toBoldPrediction(row, viewerId, nameById, usernameById)), weekGames, players };
}
