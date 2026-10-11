import type { createClient } from "@/lib/supabase/server";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * The viewer's accepted friends, so their takes can lead a prompt's discussion.
 * A failed read costs the "Friend takes" section, never the page.
 */
export async function fetchFriendIds(supabase: SupabaseServerClient, viewerId: string | null): Promise<Set<string>> {
  if (!viewerId) return new Set();
  try {
    const { data } = await supabase.rpc("list_friends");
    return new Set((data ?? []).map((friend) => friend.profile_id));
  } catch {
    return new Set();
  }
}
