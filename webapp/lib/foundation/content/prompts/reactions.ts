import type { TakeReaction } from "@/lib/foundation/content/prompts/types";
import type { createClient as createBrowserClient } from "@/lib/supabase/client";
import type { createClient as createServerClient } from "@/lib/supabase/server";

type SupabaseBrowserClient = ReturnType<typeof createBrowserClient>;
type SupabaseServerClient = Awaited<ReturnType<typeof createServerClient>>;

/**
 * Balls on takes (0216). A like gives the take's author a ball and a dislike
 * takes one away; the net feeds the Ball Knower score. The server decides who
 * can do what (`can_like`, `can_dislike`), so nothing here works the rules out.
 */

/** The reactions on a page of takes, keyed by take id. Takes the viewer cannot see are absent. */
export async function fetchTakeReactions(
  supabase: SupabaseServerClient,
  takeIds: string[],
): Promise<Map<string, TakeReaction>> {
  const reactions = new Map<string, TakeReaction>();
  if (!takeIds.length) return reactions;
  const { data } = await supabase.rpc("take_reaction_summary", { p_comment_ids: takeIds });
  for (const row of data ?? []) {
    reactions.set(row.comment_id, {
      net: row.net_balls,
      mine: row.my_reaction === 1 ? 1 : row.my_reaction === -1 ? -1 : 0,
      canLike: row.can_like,
      canDislike: row.can_dislike,
    });
  }
  return reactions;
}

const REACTION_MESSAGES: Record<string, string> = {
  not_authenticated: "Sign in to give balls.",
  guests_cannot_react: "Create an account to give balls.",
  take_not_found: "That take isn't available anymore.",
  cannot_react_to_own_take: "You can't give balls to your own take.",
  dislike_friends_only: "Only friends can take a ball away.",
  invalid_reaction: "That isn't a valid reaction.",
};

/** value: 1 gives a ball, -1 takes one away, 0 removes your reaction. */
export async function reactToTake(
  supabase: SupabaseBrowserClient,
  { takeId, value }: { takeId: string; value: -1 | 0 | 1 },
): Promise<{ net: number; mine: -1 | 0 | 1; error: null } | { error: string }> {
  const { data, error } = await supabase.rpc("react_to_take", { p_comment_id: takeId, p_value: value });
  if (error || !data?.[0]) return { error: REACTION_MESSAGES[error?.message ?? ""] ?? error?.message ?? "Couldn't save that. Try again." };
  const row = data[0];
  return { net: row.net_balls, mine: row.my_reaction === 1 ? 1 : row.my_reaction === -1 ? -1 : 0, error: null };
}
