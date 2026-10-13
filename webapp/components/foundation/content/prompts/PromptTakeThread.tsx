"use client";

import type { ReactNode } from "react";

import { ShareTakeButton } from "./ShareTakeButton";
import { TakeCard } from "./TakeCard";
import { TakeComposer } from "./TakeComposer";
import { TakeResponse } from "./TakeResponse";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import { isPicksPost, isPromptOpenForAnswers, totalPoints } from "@/lib/foundation/content/prompts/logic";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";

/**
 * What makes Bold Predictions a different kind of answer inside the same thread:
 * its own answer form, and predictions where other prompts show picks.
 */
export type BoldThread = {
  /** The write-up form, or a sign-up notice: shown while the post is open and the viewer hasn't answered. */
  composer: ReactNode;
  answered: boolean;
  /** The viewer's own predictions, for their card. */
  mine: ReactNode;
  /** One author's predictions, or null when they made none. */
  predictionsBy: (authorId: string | undefined) => ReactNode | null;
};

/** The take thread under a prompt: your own take, then friends', then everyone else's. */
export function PromptTakeThread({ post, displayName, avatarUrl, username, viewerCanAnswer, bold }: { post: Post; displayName: string; avatarUrl: string | null; username: string | null; viewerCanAnswer: boolean; bold?: BoldThread }) {
  const now = usePromptDeadlineNow(post);
  const open = isPromptOpenForAnswers(post, now);
  const answered = bold ? bold.answered : post.viewerAnswered;
  const canSubmit = viewerCanAnswer && open && !answered;
  // What a take opens onto: the picks, or for Bold Predictions the predictions.
  const picksOf = (take: Comment): ReactNode | null => (bold ? bold.predictionsBy(take.authorId) : take.response ? <TakeResponse post={post} response={take.response} isViewer={false} /> : null);
  const viewerTake = post.comments.find((item) => item.isViewer && item.postedWithPick);
  // Every answer is a take, empty when the player wrote nothing. Friends lead,
  // then takes with words, then bare answers — friends' bare answers first.
  const others = post.comments.filter((item) => !item.isViewer);
  const withWords = (item: Comment) => item.body.trim() !== "";
  const friendTakes = others.filter((item) => item.isFriend && withWords(item));
  const friendAnswers = others.filter((item) => item.isFriend && !withWords(item));
  const otherTakes = others.filter((item) => !item.isFriend && withWords(item));
  const otherAnswers = others.filter((item) => !item.isFriend && !withWords(item));
  const points = bold ? null : totalPoints(post);

  // Answering always leaves a take (0208), so the viewer's card normally has a
  // thread; the placeholder only covers a read that races the answer landing.
  const youComment: Comment | null = answered
    ? (viewerTake ?? { id: `you-${post.id}`, author: displayName, body: "", createdAt: post.createdAt, isViewer: true, postedWithPick: true, replies: [] })
    : null;

  return (
    <section aria-label="The thread" className="mt-5 w-full pb-16">
      <div className="flex flex-col gap-5">
        {bold ? (open && !answered ? bold.composer : null) : canSubmit ? <TakeComposer post={post} displayName={displayName} avatarUrl={avatarUrl} username={username} /> : null}
        {!canSubmit && !answered && viewerCanAnswer && !(open && bold) ? (
          <p className="rounded-card border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">{bold ? "You did not make predictions for this prompt." : "You did not make picks for this prompt."}</p>
        ) : null}

        {youComment ? (
          <TakeCard
            comment={youComment}
            isYou
            avatarUrl={avatarUrl}
            commentHref={viewerTake ? `/prompts/${post.id}/takes/${viewerTake.id}` : undefined}
            expandedByDefault
            footer={
              points !== null ? (
                <span className={`grade-scoremark grade-scoremark--standings ${points > 0 ? "grade-scoremark--elite" : "grade-scoremark--rough"}`}>+{points}</span>
              ) : undefined
            }
          >
            {bold ? bold.mine : <TakeResponse post={post} response={post.viewerResponse ?? {}} />}
          </TakeCard>
        ) : null}

        {youComment && (isPicksPost(post) || post.templateKind === "power_rankings") ? (
          <ShareTakeButton post={post} responses={post.viewerResponse ?? {}} />
        ) : null}

        {/* Account readers unlock the discussion by answering, or when the prompt closes (nothing left to copy). Public visitors can never answer, so it is simply readable. */}
        {(answered || !viewerCanAnswer || !open) ? (
          <>
            <TakeList label="Friend takes" post={post} takes={friendTakes} picksOf={picksOf} />
            <TakeList label="Friend answers" post={post} takes={friendAnswers} picksOf={picksOf} />
            <TakeList label="Other takes" post={post} takes={otherTakes} picksOf={picksOf} />
            <TakeList label="Other answers" post={post} takes={otherAnswers} picksOf={picksOf} />
          </>
        ) : null}
      </div>
    </section>
  );
}

function TakeList({ label, post, takes, picksOf }: { label: string; post: Post; takes: Comment[]; picksOf: (take: Comment) => ReactNode | null }) {
  if (!takes.length) return null;
  return (
    <div className="flex flex-col gap-3" aria-label={label}>
      <h2 className="px-1 type-label text-fg-muted">{label}</h2>
      {takes.map((take) => {
        const picks = picksOf(take);
        return (
          <TakeCard key={take.id} comment={take} commentHref={`/prompts/${post.id}/takes/${take.id}`} collapsedByDefault={Boolean(picks)}>
            {picks}
          </TakeCard>
        );
      })}
    </div>
  );
}
