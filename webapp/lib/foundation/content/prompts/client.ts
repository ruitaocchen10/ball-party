import { track } from "@/lib/foundation/analytics/client";
import type { Slot, TemplateKind } from "@/lib/foundation/content/prompts/types";
import type { createClient } from "@/lib/supabase/client";
import { promptErrorMessage } from "@/lib/foundation/content/prompts/messages";

type SupabaseBrowserClient = ReturnType<typeof createClient>;

/**
 * Direct client → prompts.* RPC calls, same idiom HigherOrLowerMatch and
 * AuctionMatch use for their own moves (see components/higher-or-lower/
 * HigherOrLowerMatch.tsx's makeCall): a server-action round trip per
 * interaction isn't needed here since there's no redirect involved, just a
 * local UI update. Errors come back already flattened through
 * lib/prompts/messages.ts, matching lib/lobbies/messages.ts's posture.
 */

export async function submitPromptResponse(
  supabase: SupabaseBrowserClient,
  { postId, choices, comment }: { postId: string; choices: Record<string, string[]>; comment?: string },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("submit_response", {
    p_post_id: postId,
    p_choices: choices,
    ...(comment ? { p_comment: comment } : {}),
  });
  if (!error) track("prompt_answered", { post_id: postId });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/**
 * Posts a take (no `parentCommentId`) or a reply to one (with it). The RPC
 * itself is the only thing enforcing that a reply can't target another
 * reply — see 0102's prompts.post_comment.
 */
export async function postComment(
  supabase: SupabaseBrowserClient,
  { postId, body, parentCommentId }: { postId: string; body: string; parentCommentId?: string },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("post_comment", {
    p_post_id: postId,
    p_body: body,
    ...(parentCommentId ? { p_parent_comment_id: parentCommentId } : {}),
  });
  if (!error) track("take_posted", { post_id: postId, is_reply: Boolean(parentCommentId) });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/**
 * p_slots shape create_post (0095) expects — see that migration's comment
 * on create_post for the full contract. excludes_slot_indexes is built by
 * resolving each Slot.excludesSlotIds entry to its position in this same
 * `slots` array: the RPC hasn't assigned real slot ids yet when this runs,
 * only this array's order, which is exactly what buildCustomMultiSlots in
 * ComposerFields.tsx already keys its own excludesSlotIds off of.
 */
function toCreatePostSlots(slots: Slot[]) {
  const indexById = new Map(slots.map((slot, index) => [slot.id, index]));
  return slots.map((slot) => ({
    label: slot.label,
    shape: slot.shape,
    pick_count: slot.pickCount ?? null,
    points: slot.points,
    excludes_slot_indexes: (slot.excludesSlotIds ?? [])
      .map((id) => indexById.get(id))
      .filter((index): index is number => index !== undefined),
    source_game_id: slot.sourceGameId ?? null,
    player_search: slot.playerSearch ?? false,
    options: slot.options.map((option, index) => ({
      label: option.label,
      sublabel: option.sublabel ?? null,
      team_code: option.teamCode ?? null,
      headshot_url: option.headshotUrl ?? null,
      cover_position: option.coverPosition ?? null,
      margin: option.margin ?? null,
      sort_order: index,
    })),
  }));
}

/**
 * A winner-pick post is resolved from nflverse instead of waiting for an
 * admin. Each winner slot carries its own source game id (rather than the
 * post carrying one id), so this works for both a single Game Pick and a
 * multi-game Weekly Picks post.
 */
export type PromptResolutionSource = { provider: "nflverse"; rule: "winner" };

export type CreatePostParams = {
  templateKind: TemplateKind;
  templateName: string;
  caption: string;
  promptText: string;
  resolutionCriteria: string;
  lockAt: string;
  slots: Slot[];
  resolutionSource?: PromptResolutionSource;
  isOpinion?: boolean;
  coverTeamCodes?: string[];
  /** Defaults to true; false skips the iOS push for this post (0206). */
  sendPush?: boolean;
};

/**
 * The named arguments prompts.create_post takes. The calendar stores exactly
 * this as a draft (0215), so a scheduled prompt opens through the same call
 * and the same checks as one published now.
 */
export function buildCreatePostArgs(params: CreatePostParams) {
  return {
    p_template_kind: params.templateKind,
    p_template_name: params.templateName,
    p_caption: params.caption,
    p_prompt_text: params.promptText,
    p_resolution_criteria: params.resolutionCriteria,
    p_lock_at: params.lockAt,
    p_slots: toCreatePostSlots(params.slots),
    p_is_opinion: params.isOpinion ?? false,
    p_send_push: params.sendPush ?? true,
    ...(params.coverTeamCodes ? { p_cover_team_codes: params.coverTeamCodes } : {}),
    ...(params.resolutionSource
      ? {
          p_resolution_source: {
            provider: params.resolutionSource.provider,
            rule: params.resolutionSource.rule,
          },
        }
      : {}),
  };
}

export async function createPromptPost(
  supabase: SupabaseBrowserClient,
  params: CreatePostParams,
): Promise<{ id: string } | { error: string }> {
  const { data, error } = await supabase.schema("prompts").rpc("create_post", buildCreatePostArgs(params));
  if (error) return { error: promptErrorMessage(error.message) };
  return { id: data };
}

/**
 * Admin grading for a post auto_resolve_tick doesn't cover (0096 only grades
 * game_pick posts with a resolution source). `answers` is {slotId: [correct
 * option ids]} in rank order, the shape prompts.resolve_post (0095) takes —
 * every slot on the post needs an entry, since a post resolves as a whole.
 */
export async function resolvePromptPost(
  supabase: SupabaseBrowserClient,
  { postId, answers }: { postId: string; answers: Record<string, string[]> },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("resolve_post", {
    p_post_id: postId,
    p_answers: answers,
  });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/** Closes a post with no grading; the reason is what the Posts list shows afterwards. */
export async function voidPromptPost(
  supabase: SupabaseBrowserClient,
  { postId, reason }: { postId: string; reason: string },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("void_post", {
    p_post_id: postId,
    p_reason: reason,
  });
  return { error: error ? promptErrorMessage(error.message) : null };
}

/** Permanently removes a post and, by cascade, its responses, comments and predictions. Any status. */
export async function deletePromptPost(
  supabase: SupabaseBrowserClient,
  { postId }: { postId: string },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("delete_post", { p_post_id: postId });
  return { error: error ? promptErrorMessage(error.message) : null };
}
