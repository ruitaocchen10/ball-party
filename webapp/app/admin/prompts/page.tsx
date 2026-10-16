import { notFound, redirect } from "next/navigation";

import { PromptComposerShell } from "@/components/foundation/content/prompts/PromptComposerShell";
import type { ComposerSlot } from "@/components/foundation/content/prompts/PromptPostUI";
import { easternDate, fetchScheduleSlot } from "@/lib/foundation/content/prompts/schedule";
import type { Player } from "@/lib/foundation/content/prompts/types";
import { fetchNflPlayers } from "@/lib/foundation/content/nfl/players";
import { fetchNflSchedule, type NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { createClient } from "@/lib/supabase/server";

/**
 * PROTOTYPE UI, REAL DATA. The compose-from-scratch admin screen — write a
 * prompt directly, with no draft or pipeline behind it. Auth gating for all
 * of /admin/* lives once in app/admin/layout.tsx, not here — this only
 * reads the admin's own display name, for the composer's live preview.
 */
export default async function AdminPromptsPage({ searchParams }: { searchParams: Promise<{ slot?: string }> }) {
  const { slot: slotId } = await searchParams;
  const supabase = await createClient();

  // Opened from the calendar (/admin) or the queue: compose into that slot.
  let slot: ComposerSlot | undefined;
  if (slotId) {
    const detail = await fetchScheduleSlot(supabase, slotId);
    if (!detail) notFound();
    // A slot that has opened is the live post now; edit it from Posts.
    if (detail.state === "published") redirect(detail.opens_at ? `/admin?start=${easternDate(detail.opens_at)}` : "/admin");
    slot = {
      id: detail.id,
      kind: detail.kind,
      gameId: detail.game_id,
      season: detail.season,
      week: detail.week,
      opensAt: detail.opens_at,
      lockAt: detail.lock_at,
      state: detail.state,
      publishError: detail.publish_error,
      composer: (detail.payload?.composer as Record<string, unknown> | undefined) ?? null,
    };
  }

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const { data: profile } = claims?.sub
    ? await supabase.from("profiles").select("display_name").eq("id", claims.sub).single()
    : { data: null };
  const displayName = profile?.display_name ?? (claims?.email as string | undefined) ?? "Ball Party";

  let games: NflScheduleGame[] = [];
  try {
    games = await fetchNflSchedule(supabase);
  } catch {
    // The composer remains usable for its non-schedule templates while the
    // schedule is unreadable; game templates explain the missing pool.
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

  return <PromptComposerShell key={slot?.id ?? "new"} displayName={displayName} games={games} players={players} slot={slot} />;
}
