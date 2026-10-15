import type { ListKind, ListPlayer, ListSummary, ListUpdate, ListVersion } from "./types";
import type { createClient } from "@/lib/supabase/server";

type Client = Awaited<ReturnType<typeof createClient>>;

const itemKind = (value: string): "team" | "player" => (value === "player" ? "player" : "team");

/** The kinds of list a player can keep, in the order the tab shows them. */
export async function fetchListKinds(supabase: Client): Promise<ListKind[]> {
  const { data } = await supabase.from("ranking_list_kinds").select("id, label, item_kind, sizes");
  const order = ["power_rankings", "qb", "rb", "wr"];
  return (data ?? [])
    .map((row) => ({ id: row.id, label: row.label, itemKind: itemKind(row.item_kind), sizes: [...row.sizes].sort((a, b) => a - b) }))
    .sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
}

/**
 * A player's lists: the newest version of each kind they keep. The database
 * decides who may see them (get_ranking_lists), so a private profile or a
 * blocked viewer simply gets nothing.
 */
export async function fetchLists(supabase: Client, username: string): Promise<{ lists: ListSummary[]; failed: boolean }> {
  const { data, error } = await supabase.rpc("get_ranking_lists", { p_username: username });
  if (error) return { lists: [], failed: true };
  return {
    failed: false,
    lists: (data ?? []).map((row) => ({
      kind: row.kind,
      label: row.label,
      itemKind: itemKind(row.item_kind),
      versionId: row.version_id,
      versionNo: row.version_no,
      savedAt: row.created_at,
      versionCount: row.version_count,
      items: row.items ?? [],
      note: row.note ?? null,
      previousItems: row.prev_items ?? null,
    })),
  };
}

/** One list's whole history, newest first. Notes and cards come back only for the owner and their friends. */
export async function fetchListHistory(supabase: Client, username: string, kind: string): Promise<{ versions: ListVersion[]; failed: boolean }> {
  const { data, error } = await supabase.rpc("get_ranking_list", { p_username: username, p_kind: kind });
  if (error) return { versions: [], failed: true };
  return {
    failed: false,
    versions: (data ?? []).map((row) => ({
      id: row.version_id,
      versionNo: row.version_no,
      source: row.source === "prompt" ? "prompt" : "edit",
      promptPostId: row.post_id,
      updatePostId: row.update_post_id,
      note: row.note,
      savedAt: row.created_at,
      isCurrent: row.is_current,
      items: row.items ?? [],
    })),
  };
}

/** Names and faces for the player ids in some lists. Unknown ids are left out. */
export async function fetchListPlayers(supabase: Client, ids: string[]): Promise<Record<string, ListPlayer>> {
  const unique = [...new Set(ids)];
  if (!unique.length) return {};
  const { data } = await supabase.rpc("ranking_players", { p_ids: unique });
  return Object.fromEntries(
    (data ?? []).map((row) => [row.player_id, { id: row.player_id, name: row.display_name, position: row.position, team: row.team, headshotUrl: row.headshot_url }]),
  );
}

/** The prompt that feeds a kind of list while it is open, if any: the editor sends the player there. */
export async function fetchOpenListPrompt(supabase: Client, kind: string): Promise<string | null> {
  const { data } = await supabase
    .from("prompt_posts")
    .select("id")
    .eq("ranking_kind", kind)
    .eq("status", "open")
    .gt("lock_at", new Date().toISOString())
    .neq("template_kind", "ranking_update")
    .order("created_at", { ascending: false })
    .limit(1);
  return data?.[0]?.id ?? null;
}

/** The viewer's and their friends' published edits, newest first. */
export async function fetchListUpdates(
  supabase: Client,
  { limit = 20, before = null, postId = null }: { limit?: number; before?: string | null; postId?: string | null } = {},
): Promise<ListUpdate[]> {
  const { data, error } = await supabase.rpc("friend_list_updates", {
    p_limit: limit,
    ...(before ? { p_before: before } : {}),
    ...(postId ? { p_post_id: postId } : {}),
  });
  if (error) return [];
  return (data ?? []).map((row) => ({
    postId: row.post_id,
    authorId: row.author_id,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    kind: row.kind,
    label: row.label,
    itemKind: itemKind(row.item_kind),
    versionNo: row.version_no,
    note: row.note,
    savedAt: row.created_at,
    items: row.items ?? [],
    previousItems: row.prev_items,
  }));
}

/** One update card by its post id, or null when it does not exist or the viewer is not a friend. */
export async function fetchListUpdate(supabase: Client, postId: string): Promise<ListUpdate | null> {
  return (await fetchListUpdates(supabase, { limit: 1, postId }))[0] ?? null;
}

export type ListReply = {
  id: string;
  authorName: string;
  authorUsername: string | null;
  avatarUrl: string | null;
  body: string;
  createdAt: string;
  isViewer: boolean;
};

/**
 * The replies under an update card, and the id of the take they hang on (the
 * card's note). Row-level security shows them only to the author and their friends.
 */
export async function fetchListThread(supabase: Client, postId: string, viewerId: string): Promise<{ takeId: string | null; replies: ListReply[] }> {
  const { data: all } = await supabase
    .from("prompt_comments")
    .select("id, author_id, body, created_at, parent_comment_id")
    .eq("post_id", postId)
    .order("created_at");
  const takeId = (all ?? []).find((row) => row.parent_comment_id === null)?.id ?? null;
  const rows = (all ?? []).filter((row) => row.parent_comment_id !== null);
  if (!rows.length) return { takeId, replies: [] };
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, display_name, avatar_url, username")
    .in("id", [...new Set(rows.map((row) => row.author_id))]);
  const byId = new Map((profiles ?? []).map((profile) => [profile.id, profile]));
  const replies = rows.map((row) => ({
    id: row.id,
    authorName: byId.get(row.author_id)?.display_name ?? "Player",
    authorUsername: byId.get(row.author_id)?.username ?? null,
    avatarUrl: byId.get(row.author_id)?.avatar_url ?? null,
    body: row.body,
    createdAt: row.created_at,
    isViewer: row.author_id === viewerId,
  }));
  return { takeId, replies };
}
