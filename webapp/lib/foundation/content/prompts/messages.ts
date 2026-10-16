/**
 * The machine-readable strings prompts.* RPCs raise (see
 * supabase/migrations/20260909121500_0095_prompts_write_api.sql). Anything
 * absent from this map is a bug rather than a player-facing condition, so it
 * surfaces raw instead of being flattened into a friendly lie — same posture
 * as lib/lobbies/messages.ts.
 */
export const PROMPT_MESSAGES: Record<string, string> = {
  not_authenticated: "Sign in to answer.",
  post_not_found: "This prompt no longer exists.",
  post_locked: "This prompt has locked — no more picks.",
  incomplete_slot: "Finish every pick before locking in.",
  invalid_option: "One of those picks isn't valid anymore. Refresh and try again.",
  option_already_used: "You've already used that team in another pick on this prompt.",
  invalid_cover_teams: "Choose exactly six different teams for the cover art.",
  invalid_weekly_awards: "Weekly Awards needs six slots: two team picks, a game, and three player searches.",
  invalid_cover_options: "Choose four different players for the prompt art.",
  not_authorized: "Only the admin can do that.",
  not_resolvable: "This prompt has already been resolved or voided.",
  opinion_not_resolvable: "Opinion prompts have no right answer, so they can't be resolved.",
  missing_answer: "Every pick needs an answer before this can resolve.",
  reason_required: "Give a reason before voiding.",
  not_voidable: "This prompt can no longer be voided.",
  parent_not_found: "That take isn't available anymore. Refresh and try again.",
  nested_reply: "You can only reply to a take, not to another reply.",
  too_many_predictions: "A response holds at most five predictions.",
  no_predictions: "Add at least one prediction before you lock in.",
  already_answered: "You've already locked in your predictions.",
  invalid_target: "That tag isn't valid for this post anymore. Pick another.",
  not_bold_predictions: "This post doesn't take predictions.",
  slot_not_editable: "That slot has already opened, or no longer exists.",
  slot_not_found: "That slot no longer exists.",
  invalid_payload: "That draft couldn't be saved.",
};

export function promptErrorMessage(message: string): string {
  // mark_ready (0215) names the missing steps: "not_ready: No open time; No caption".
  if (message.startsWith("not_ready: ")) return `Not ready yet — ${message.slice("not_ready: ".length)}.`;
  return PROMPT_MESSAGES[message] ?? message;
}
