/**
 * What save_ranking_list raises (supabase/migrations/20261112110000_0211).
 * `edit_limit` and `prompt_open` carry extra detail the caller formats, so
 * they are handled by saveErrorMessage rather than listed here.
 */
export const LIST_MESSAGES: Record<string, string> = {
  not_authenticated: "Sign in with an account to keep lists.",
  no_change: "That's the same as your saved list. Move something first.",
  note_too_long: "Keep the note to 280 characters.",
  invalid_ranking_size: "That list can't be that long.",
  invalid_ranking_items: "One of those picks isn't valid. Refresh and try again.",
  unknown_ranking_kind: "That list doesn't exist.",
};

/** The time the next save opens, in the viewer's own words, or null when the detail is not a time. */
export function nextSaveLabel(detail: string | null | undefined, now: Date = new Date()): string | null {
  if (!detail) return null;
  const at = new Date(detail);
  if (Number.isNaN(at.getTime())) return null;
  const minutes = Math.max(1, Math.round((at.getTime() - now.getTime()) / 60000));
  if (minutes < 60) return `in ${minutes} minute${minutes === 1 ? "" : "s"}`;
  const hours = Math.round(minutes / 60);
  return `in ${hours} hour${hours === 1 ? "" : "s"}`;
}

export function saveErrorMessage(message: string, detail?: string | null, now?: Date): string {
  if (message === "edit_limit") {
    const when = nextSaveLabel(detail, now);
    return when ? `You saved this list in the last 24 hours. You can save again ${when}.` : "You saved this list in the last 24 hours. Try again later.";
  }
  if (message === "prompt_open") return "This week's prompt for this list is open. Answer it to update your list.";
  return LIST_MESSAGES[message] ?? message;
}
