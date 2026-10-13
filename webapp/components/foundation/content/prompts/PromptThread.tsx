"use client";

import { BoldPredictionsBoard } from "./BoldPredictionsBoard";
import { PromptTakeThread } from "./PromptTakeThread";
import type { BoldPredictionBoardData } from "@/lib/foundation/content/prompts/boldPredictions";
import type { Post } from "@/lib/foundation/content/prompts/types";

/**
 * A prompt's detail page, in the same feed column as the Huddle cards: your own take posts at the top —
 * composer before you've answered and an ordinary TakeCard after. Account
 * readers unlock other takes by making a pick; public readers can browse the
 * discussion but never receive a response or reply control.
 */
export function PromptThread({ post, displayName, avatarUrl, username = null, viewerCanAnswer = true, boldPredictions }: { post: Post; displayName: string; avatarUrl: string | null; username?: string | null; viewerCanAnswer?: boolean; boldPredictions?: BoldPredictionBoardData }) {
  // Bold Predictions is the same thread with its own answer form and predictions in place of picks.
  if (post.templateKind === "bold_predictions" && boldPredictions) {
    return <BoldPredictionsBoard post={post} data={boldPredictions} viewerCanAnswer={viewerCanAnswer} displayName={displayName} avatarUrl={avatarUrl} username={username} />;
  }
  return <PromptTakeThread post={post} displayName={displayName} avatarUrl={avatarUrl} username={username} viewerCanAnswer={viewerCanAnswer} />;
}
