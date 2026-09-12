import { AdminComposerShell } from "@/components/social/AdminComposerShell";
import type { Player } from "@/components/social/types";
import { fetchNflPlayers } from "@/lib/nfl/players";
import { fetchNflSchedule, type NflScheduleGame } from "@/lib/nfl/schedule";
import { createClient } from "@/lib/supabase/server";

/**
 * PROTOTYPE UI, REAL DATA. The compose-from-scratch admin screen — write a
 * prompt directly, with no draft or pipeline behind it. Auth gating for all
 * of /admin/* lives once in app/admin/layout.tsx, not here — this only
 * reads the admin's own display name, for the composer's live preview.
 */
export default async function AdminPromptsPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const { data: profile } = claims?.sub
    ? await supabase.from("profiles").select("display_name").eq("id", claims.sub).single()
    : { data: null };
  const displayName = profile?.display_name ?? (claims?.email as string | undefined) ?? "Ball Party";

  let games: NflScheduleGame[] = [];
  try {
    games = await fetchNflSchedule();
  } catch {
    // The composer remains usable for its non-schedule templates during a
    // temporary upstream outage; game templates explain the missing pool.
  }

  let players: Player[] = [];
  try {
    players = await fetchNflPlayers();
  } catch {
    // A prompt can still be composed during a temporary nflverse outage.
    // This is card-safe data only; the fallback never exposes pool scoring.
    const { data: playerRows } = await supabase.schema("prompts").rpc("player_options");
    players = (playerRows ?? []).map((player) => ({
      id: player.player_id,
      name: player.display_name,
      position: player.position,
      team: player.team,
      headshotUrl: player.headshot_url ?? "",
    }));
  }

  return <AdminComposerShell displayName={displayName} games={games} players={players} />;
}
