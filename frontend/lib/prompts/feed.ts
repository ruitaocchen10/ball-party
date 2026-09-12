import type { Comment, LifecycleStatus, Option, Post, Slot, SlotShape, TemplateKind } from "@/components/social/types";
import type { Database } from "@/lib/supabase/database.types";
import type { createClient } from "@/lib/supabase/server";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

type PostRow = Database["public"]["Tables"]["prompt_posts"]["Row"];
type SlotRow = Database["public"]["Tables"]["prompt_slots"]["Row"];
type OptionRow = Database["public"]["Tables"]["prompt_slot_options"]["Row"];
type ExclusionRow = Database["public"]["Tables"]["prompt_slot_exclusions"]["Row"];
type ResponseRow = Database["public"]["Tables"]["prompt_responses"]["Row"];
type CommentRow = Database["public"]["Tables"]["prompt_comments"]["Row"];

/**
 * The real feed behind components/social/ — reads the tables and
 * RPC that supabase/migrations/20260909120000_0094_prompts_schema.sql and
 * 20260909121500_0095_prompts_write_api.sql built, and shapes them into the
 * same `Post[]` the prototype UI already renders from mockData.ts. Every
 * table read here goes through the request-scoped, RLS-bound client
 * (lib/supabase/server.ts) — nothing bypasses a policy.
 *
 * Flat queries joined in JS rather than nested PostgREST embeds, matching
 * how app/match/[id]/page.tsx and HigherOrLowerMatch's refetch() already do
 * this in this codebase: simpler to reason about, and sidesteps the embed
 * ambiguity a table with two FKs to the same relation would otherwise hit
 * (prompt_slot_exclusions has exactly that shape).
 *
 * `viewerId` is null for a signed-out visitor; app/page.tsx only
 * calls this once someone is signed in, since RLS grants prompt tables to
 * `authenticated` only — an anonymous request would just get refused.
 */
export async function fetchPromptFeed(supabase: SupabaseServerClient, viewerId: string | null): Promise<Post[]> {
  const { data: postRows } = await supabase
    .from("prompt_posts")
    .select("*")
    .order("created_at", { ascending: false });
  if (!postRows || postRows.length === 0) return [];

  const postIds = postRows.map((row) => row.id);

  const [slotRows, responseRows, commentRows] = await Promise.all([
    supabase.from("prompt_slots").select("*").in("post_id", postIds).order("sort_order").then((r) => r.data ?? ([] as SlotRow[])),
    // Own rows only — prompt_responses' RLS is profile_id = auth.uid(), so
    // this can never return anyone else's pick regardless of filter.
    viewerId
      ? supabase.from("prompt_responses").select("*").eq("profile_id", viewerId).in("post_id", postIds).then((r) => r.data ?? ([] as ResponseRow[]))
      : Promise.resolve([] as ResponseRow[]),
    supabase.from("prompt_comments").select("*").in("post_id", postIds).order("created_at").then((r) => r.data ?? ([] as CommentRow[])),
  ]);

  const slotIds = slotRows.map((row) => row.id);
  const [optionRows, exclusionRows] = await Promise.all([
    slotIds.length
      ? supabase.from("prompt_slot_options").select("*").in("slot_id", slotIds).order("sort_order").then((r) => r.data ?? ([] as OptionRow[]))
      : Promise.resolve([] as OptionRow[]),
    slotIds.length
      ? supabase.from("prompt_slot_exclusions").select("*").in("slot_id", slotIds).then((r) => r.data ?? ([] as ExclusionRow[]))
      : Promise.resolve([] as ExclusionRow[]),
  ]);

  const authorIds = new Set<string>();
  postRows.forEach((row) => authorIds.add(row.author_id));
  commentRows.forEach((row) => authorIds.add(row.author_id));
  const { data: profileRows } = authorIds.size
    ? await supabase.from("profiles").select("id, display_name").in("id", [...authorIds])
    : { data: [] as { id: string; display_name: string }[] };
  const nameById = new Map((profileRows ?? []).map((row) => [row.id, row.display_name]));

  const optionsBySlot = groupBy(optionRows, (row) => row.slot_id);
  const exclusionsBySlot = groupBy(exclusionRows, (row) => row.slot_id);
  const slotsByPost = groupBy(slotRows, (row) => row.post_id);
  const responsesByPost = groupBy(responseRows, (row) => row.post_id);
  const commentsByPost = groupBy(commentRows, (row) => row.post_id);

  // A revealed view (aggregate bars + any correct/wrong highlighting) only
  // ever shows once a post isn't open-and-unanswered — see types.ts's
  // Post.aggregate comment. post_aggregates is the only sanctioned way to
  // see anyone else's pick (prompt_responses' RLS is own-row-only), so it's
  // fetched only for the posts that actually need it.
  const postsNeedingAggregate = postRows.filter(
    (row) => row.status !== "open" || (responsesByPost.get(row.id)?.length ?? 0) > 0,
  );
  const aggregateResults = await Promise.all(
    postsNeedingAggregate.map((row) =>
      supabase
        .schema("prompts")
        .rpc("post_aggregates", { p_post_id: row.id })
        .then((result) => ({ postId: row.id, rows: result.data ?? [] })),
    ),
  );
  const aggregateByPost = new Map(aggregateResults.map(({ postId, rows }) => [postId, rows]));

  return postRows.map((row) => mapPost(row, {
    slotsByPost,
    optionsBySlot,
    exclusionsBySlot,
    responsesByPost,
    commentsByPost,
    nameById,
    viewerId,
    aggregateByPost,
  }));
}

function mapPost(
  row: PostRow,
  ctx: {
    slotsByPost: Map<string, SlotRow[]>;
    optionsBySlot: Map<string, OptionRow[]>;
    exclusionsBySlot: Map<string, ExclusionRow[]>;
    responsesByPost: Map<string, ResponseRow[]>;
    commentsByPost: Map<string, CommentRow[]>;
    nameById: Map<string, string>;
    viewerId: string | null;
    aggregateByPost: Map<string, { slot_id: string; option_id: string; pct: number | null; total_responses: number | null }[]>;
  },
): Post {
  const slots: Slot[] = (ctx.slotsByPost.get(row.id) ?? []).map((slotRow) => ({
    id: slotRow.id,
    label: slotRow.label,
    // Trusts the `shape`/`check` constraints on prompt_slots and
    // prompt_posts (0094) rather than re-validating the union here.
    shape: slotRow.shape as SlotShape,
    pickCount: slotRow.pick_count ?? undefined,
    points: slotRow.points,
    sourceGameId: slotRow.source_game_id ?? undefined,
    correct: slotRow.correct_option_ids ?? undefined,
    excludesSlotIds: (ctx.exclusionsBySlot.get(slotRow.id) ?? []).map((ex) => ex.excluded_slot_id),
    options: (ctx.optionsBySlot.get(slotRow.id) ?? []).map(
      (optionRow): Option => ({
        id: optionRow.id,
        label: optionRow.label,
        sublabel: optionRow.sublabel ?? undefined,
        teamCode: optionRow.team_code ?? undefined,
        headshotUrl: optionRow.headshot_url ?? undefined,
      }),
    ),
  }));

  const myResponses = ctx.responsesByPost.get(row.id) ?? [];
  const viewerAnswered = myResponses.length > 0;
  const viewerResponse = viewerAnswered
    ? Object.fromEntries(myResponses.map((r) => [r.slot_id, r.chosen_option_ids]))
    : undefined;
  const viewerPointsAwarded =
    row.status === "resolved" && viewerAnswered
      ? myResponses.reduce((sum, r) => sum + (r.points_earned ?? 0), 0)
      : undefined;

  const comments: Comment[] = (ctx.commentsByPost.get(row.id) ?? []).map((c) => ({
    id: c.id,
    author: ctx.nameById.get(c.author_id) ?? "Unknown",
    body: c.body,
    createdAt: c.created_at,
    isViewer: c.author_id === ctx.viewerId,
    postedWithPick: c.posted_with_pick,
  }));

  const aggregateRows = ctx.aggregateByPost.get(row.id);
  let aggregate: Post["aggregate"];
  let responseCount = 0;
  if (aggregateRows) {
    aggregate = {};
    for (const slot of slots) aggregate[slot.id] = {};
    for (const agg of aggregateRows) {
      aggregate[agg.slot_id][agg.option_id] = agg.pct ?? 0;
      responseCount = Math.max(responseCount, agg.total_responses ?? 0);
    }
  }

  return {
    id: row.id,
    templateKind: row.template_kind as TemplateKind,
    templateName: row.template_name,
    author: ctx.nameById.get(row.author_id) ?? "Ball Party",
    caption: row.caption,
    createdAt: row.created_at,
    promptText: row.prompt_text,
    resolutionCriteria: row.resolution_criteria,
    lockAt: row.lock_at,
    status: row.status as LifecycleStatus,
    voidReason: row.void_reason ?? undefined,
    slots,
    comments,
    responseCount,
    viewerAnswered,
    viewerResponse,
    viewerPointsAwarded,
    aggregate,
  };
}

function groupBy<T, K>(rows: T[], key: (row: T) => K): Map<K, T[]> {
  const map = new Map<K, T[]>();
  for (const row of rows) {
    const k = key(row);
    const bucket = map.get(k);
    if (bucket) bucket.push(row);
    else map.set(k, [row]);
  }
  return map;
}
