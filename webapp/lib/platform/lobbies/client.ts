import { type createClient } from "@/lib/supabase/client";

/** Browser equivalent of the server action's idempotent, deadlock-safe join. */
export async function joinLobbyFromBrowser(
  supabase: ReturnType<typeof createClient>,
  code: string,
) {
  let result = await supabase.rpc("join_lobby", { p_code: code });
  if (result.error?.code === "40P01") {
    result = await supabase.rpc("join_lobby", { p_code: code });
  }
  return result;
}
