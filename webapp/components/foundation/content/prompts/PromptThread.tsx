"use client";

import { BoldPredictionsBoard } from "./BoldPredictionsBoard";
import { ShareTakeButton } from "./ShareTakeButton";
import { TakeCard } from "./TakeCard";
import { TakeComposer } from "./TakeComposer";
import { TakeResponse } from "./TakeResponse";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import { isPicksPost, isPromptOpenForAnswers, totalPoints } from "@/lib/foundation/content/prompts/logic";
import type { BoldPredictionBoardData } from "@/lib/foundation/content/prompts/boldPredictions";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";

/**
 * A prompt's detail page, in the same feed column as the Huddle cards: your own take posts at the top —
 * composer before you've answered and an ordinary TakeCard after. Account
 * readers unlock other takes by making a pick; public readers can browse the
 * discussion but never receive a response or reply control.
 */
export function PromptThread({ post, displayName, avatarUrl, username = null, viewerCanAnswer = true, boldPredictions }: { post: Post; displayName: string; avatarUrl: string | null; username?: string | null; viewerCanAnswer?: boolean; boldPredictions?: BoldPredictionBoardData }) {
  // Bold Predictions has no picks or takes to unlock — its own board is the whole thread.
  if (post.templateKind === "bold_predictions" && boldPredictions) {
    return <BoldPredictionsBoard post={post} data={boldPredictions} viewerCanAnswer={viewerCanAnswer} displayName={displayName} avatarUrl={avatarUrl} username={username} />;
  }
  return <PickThread post={post} displayName={displayName} avatarUrl={avatarUrl} username={username} viewerCanAnswer={viewerCanAnswer} />;
}

function PickThread({ post, displayName, avatarUrl, username, viewerCanAnswer }: { post: Post; displayName: string; avatarUrl: string | null; username: string | null; viewerCanAnswer: boolean }) {
  const now = usePromptDeadlineNow(post);
  const canSubmit = viewerCanAnswer && isPromptOpenForAnswers(post, now) && !post.viewerAnswered;
  const viewerTake = post.comments.find((item) => item.isViewer && item.postedWithPick);
  // A response remains the social contract for account readers. Public
  // visitors have no way to make a response, so the discussion is readable
  // rather than presenting an inaccessible gated feed.
  const otherTakes = post.comments.filter((item) => !item.isViewer);
  const points = totalPoints(post);

  // A viewer who answered without leaving a take still gets a card up top —
  // just one with no reply thread, since there's no real comment row to
  // attach a reply to.
  const youComment: Comment | null = post.viewerAnswered
    ? (viewerTake ?? { id: `you-${post.id}`, author: displayName, body: "", createdAt: post.createdAt, isViewer: true, postedWithPick: true, replies: [] })
    : null;

  return (
    <section aria-label="The thread" className="mt-5 w-full pb-16">
      <div className="flex flex-col gap-5">
        {canSubmit ? <TakeComposer post={post} displayName={displayName} avatarUrl={avatarUrl} username={username} /> : null}
        {!canSubmit && !post.viewerAnswered && viewerCanAnswer ? (
          <p className="rounded-card border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">You did not make picks for this prompt.</p>
        ) : null}

        {youComment ? (
          <TakeCard
            comment={youComment}
            isYou
            avatarUrl={avatarUrl}
            commentHref={viewerTake ? `/prompts/${post.id}/takes/${viewerTake.id}` : undefined}
            collapsedByDefault
            footer={
              <span className="flex items-center gap-3 type-label text-fg-muted">
                Picks locked in
                {points !== null ? (
                  <span className={`grade-scoremark grade-scoremark--standings ${points > 0 ? "grade-scoremark--elite" : "grade-scoremark--rough"}`}>+{points}</span>
                ) : null}
              </span>
            }
          >
            <TakeResponse post={post} response={post.viewerResponse ?? {}} />
          </TakeCard>
        ) : null}

        {youComment && (isPicksPost(post) || post.templateKind === "power_rankings") ? (
          <ShareTakeButton post={post} responses={post.viewerResponse ?? {}} />
        ) : null}

        {(post.viewerAnswered || !viewerCanAnswer) && otherTakes.length ? (
          <div className="flex flex-col gap-3" aria-label="Other takes">
            <h2 className="px-1 type-label text-fg-muted">Other takes</h2>
            {otherTakes.map((take) => (
              <TakeCard
                key={take.id}
                comment={take}
                commentHref={`/prompts/${post.id}/takes/${take.id}`}
                collapsedByDefault={Boolean(take.response)}
              >
                {take.response ? <TakeResponse post={post} response={take.response} isViewer={false} /> : null}
              </TakeCard>
            ))}
          </div>
        ) : null}
      </div>
    </section>
  );
}
