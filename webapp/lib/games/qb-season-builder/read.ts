import { isGuestViewer, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { resultFromJson, type SeasonResult } from "@/lib/games/qb-season-builder/result";
import type { createClient } from "@/lib/supabase/server";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * A finished run's saved season, or null when there is genuinely no such result
 * — an id that is not a run, a run still in play, one that was never finished.
 * Readable signed out: the run's id is the whole capability (see
 * docs/games/qb_season_builder/rules.md), which is what lets a shared link work.
 *
 * Only `result_not_found` is "no result". Anything else is the database failing
 * to answer, and it is raised rather than flattened into a missing season — a
 * blip should not tell a player their run was never saved.
 */
export async function fetchResult(supabase: SupabaseServerClient, matchId: string): Promise<SeasonResult | null> {
  const { data, error } = await supabase.schema("qb_season_builder").rpc("result", { p_match_id: matchId });
  if (error) {
    if (error.message === "result_not_found") return null;
    throw new Error(`qb_season_builder.result failed: ${error.message}`);
  }
  return resultFromJson(data);
}

/**
 * The viewer's own best score in one mode, or null when they have none to show:
 * signed out, a guest (the stat is an account feature and RLS refuses a guest
 * the row, so it is not even asked for), or no finished run in that mode yet.
 */
export async function fetchPersonalBest(
  supabase: SupabaseServerClient,
  claims: { sub?: string; is_anonymous?: boolean } | null | undefined,
  mode: SeasonResult["mode"],
): Promise<number | null> {
  if (!isSignedInViewer(claims) || isGuestViewer(claims)) return null;

  const { data } = await supabase
    .from("qb_season_builder_player_stats")
    .select("best_score")
    .eq("user_id", claims.sub)
    .eq("mode", mode)
    .maybeSingle();
  return data?.best_score ?? null;
}
