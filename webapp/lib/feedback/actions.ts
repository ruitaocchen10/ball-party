"use server";

import { createClient } from "@/lib/supabase/server";
import type { FeedbackState } from "@/lib/feedback/state";

/** Records a short, actionable note without exposing anyone else's feedback. */
export async function submitFeedback(
  _previous: FeedbackState,
  formData: FormData,
): Promise<FeedbackState> {
  const kind = String(formData.get("kind") ?? "");
  const message = String(formData.get("message") ?? "").trim();
  const submittedRoute = String(formData.get("route") ?? "").trim();

  if (kind !== "bug" && kind !== "feature") {
    return { error: "Choose whether this is a bug or a feature request.", saved: false };
  }
  if (message.length < 3 || message.length > 2_000) {
    return { error: "Feedback must be between 3 and 2,000 characters.", saved: false };
  }

  // The route is context rather than an authority boundary, but keeping it a
  // local path avoids persisting arbitrary URLs supplied by a forged form.
  const route = submittedRoute.startsWith("/") && submittedRoute.length <= 2_048 ? submittedRoute : "/";
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const reporterId = typeof data?.claims?.sub === "string" ? data.claims.sub : null;
  const { error } = await supabase.from("feedback").insert({ kind, message, route, reporter_id: reporterId });

  if (error) return { error: "We couldn’t send that feedback. Please try again.", saved: false };
  return { error: null, saved: true };
}
