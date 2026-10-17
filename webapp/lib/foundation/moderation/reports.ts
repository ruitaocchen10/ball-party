import type { createClient as createBrowserClient } from "@/lib/supabase/client";

type SupabaseBrowserClient = ReturnType<typeof createBrowserClient>;

/**
 * Reporting a take or a profile (0220). The server decides who may report what
 * and hides a reported take from its reporter at once; this is the reasons a
 * player can pick and the words for the server's refusals.
 */

export const REPORT_REASONS = [
  { value: "harassment", label: "Harassment or bullying" },
  { value: "hate", label: "Hate speech" },
  { value: "sexual", label: "Sexual content" },
  { value: "violence", label: "Violence or threats" },
  { value: "spam", label: "Spam" },
  { value: "other", label: "Something else" },
] as const;

export type ReportReason = (typeof REPORT_REASONS)[number]["value"];

const REPORT_MESSAGES: Record<string, string> = {
  account_required: "Create an account to report.",
  take_not_found: "That take isn't available anymore.",
  profile_not_found: "That profile isn't available anymore.",
  cannot_report_self: "You can't report your own take.",
};

export function reportErrorMessage(code: string | undefined): string {
  return (code && REPORT_MESSAGES[code]) || "Couldn't send that. Try again.";
}

export type ReportTarget = { kind: "take"; takeId: string } | { kind: "profile"; profileId: string };

/** Sends the report. Resolves to an error message, or null when it went through. */
export async function sendReport(
  supabase: SupabaseBrowserClient,
  target: ReportTarget,
  { reason, details }: { reason: ReportReason; details: string },
): Promise<string | null> {
  const p_details = details.trim() || undefined;
  const { error } =
    target.kind === "take"
      ? await supabase.rpc("report_take", { p_comment_id: target.takeId, p_reason: reason, p_details })
      : await supabase.rpc("report_profile", { p_user_id: target.profileId, p_reason: reason, p_details });
  return error ? reportErrorMessage(error.message) : null;
}

export type AdminAction = "dismiss" | "remove" | "ban";

export type AdminReport = {
  id: string;
  kind: "take" | "profile";
  reason: string;
  details: string | null;
  createdAt: string;
  reporterName: string;
  targetUserId: string;
  targetName: string;
  targetUsername: string | null;
  commentBody: string | null;
  postId: string | null;
  targetReportCount: number;
};

export function reasonLabel(reason: string): string {
  return REPORT_REASONS.find((r) => r.value === reason)?.label ?? reason;
}
