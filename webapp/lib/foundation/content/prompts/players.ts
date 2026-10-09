import type { createClient } from "@/lib/supabase/client";
import { promptErrorMessage } from "@/lib/foundation/content/prompts/messages";

type SupabaseBrowserClient = ReturnType<typeof createClient>;

/**
 * One row of the player directory, as prompts.search_players (0172) returns
 * it: identity fields only, no scoring data.
 */
export type PlayerResult = {
  id: string;
  name: string;
  position: string;
  team: string;
  headshotUrl: string | null;
  /** nflverse roster status: ACT, DEV, RES, INA or EXE. */
  status: string;
};

export type PlayerSearch = (query: string) => Promise<{ players: PlayerResult[]; error: string | null }>;

/** Calls prompts.search_players; a blank query is answered without a round trip. */
export async function searchPlayers(
  supabase: SupabaseBrowserClient,
  query: string,
  limit = 20,
): Promise<{ players: PlayerResult[]; error: string | null }> {
  if (!query.trim()) return { players: [], error: null };
  const { data, error } = await supabase.schema("prompts").rpc("search_players", { p_query: query, p_limit: limit });
  if (error) return { players: [], error: promptErrorMessage(error.message) };
  return {
    players: (data ?? []).map((row) => ({
      id: row.player_id,
      name: row.display_name,
      position: row.position,
      team: row.team,
      headshotUrl: row.headshot_url,
      status: row.status,
    })),
    error: null,
  };
}

const STATUS_LABELS: Record<string, string> = {
  DEV: "Practice squad",
  RES: "Reserve list",
  INA: "Inactive",
  EXE: "Exempt list",
};

/** The label shown beside a player who isn't on the active roster; null for an active one. */
export function playerStatusLabel(status: string): string | null {
  return STATUS_LABELS[status] ?? null;
}
