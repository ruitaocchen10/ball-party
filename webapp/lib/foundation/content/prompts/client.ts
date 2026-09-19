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
    options: slot.options.map((option, index) => ({
      label: option.label,
      sublabel: option.sublabel ?? null,
      team_code: option.teamCode ?? null,
      headshot_url: option.headshotUrl ?? null,
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

export async function createPromptPost(
  supabase: SupabaseBrowserClient,
  params: {
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
  },
): Promise<{ id: string } | { error: string }> {
  const { data, error } = await supabase.schema("prompts").rpc("create_post", {
    p_template_kind: params.templateKind,
    p_template_name: params.templateName,
    p_caption: params.caption,
    p_prompt_text: params.promptText,
    p_resolution_criteria: params.resolutionCriteria,
    p_lock_at: params.lockAt,
    p_slots: toCreatePostSlots(params.slots),
    p_is_opinion: params.isOpinion ?? false,
    ...(params.coverTeamCodes ? { p_cover_team_codes: params.coverTeamCodes } : {}),
    ...(params.resolutionSource
      ? {
          p_resolution_source: {
          provider: params.resolutionSource.provider,
          rule: params.resolutionSource.rule,
          },
        }
      : {}),
  });
  if (error) return { error: promptErrorMessage(error.message) };
  return { id: data };
}
