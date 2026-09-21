"use client";

import { ShareTakeButton } from "./ShareTakeButton";
import { PowerRankingsSlot, SlotFaceC, YourCalls } from "./SlotFaces";
import { TakeCard } from "./TakeCard";
import { TakeComposer } from "./TakeComposer";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import { isPicksPost, isPromptOpenForAnswers, totalPoints } from "@/lib/foundation/content/prompts/logic";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";

/**
 * A prompt's detail page, in the same feed column as the Huddle cards: your own take posts at the top —
 * composer before you've answered and an ordinary TakeCard after. Account
 * readers unlock other takes by making a pick; public readers can browse the
 * discussion but never receive a response or reply control.
 */
export function PromptThread({ post, displayName, avatarUrl, viewerCanAnswer = true }: { post: Post; displayName: string; avatarUrl: string | null; viewerCanAnswer?: boolean }) {
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
    <section aria-label="The thread" className="mt-5 w-full max-w-[760px] pb-16">
      <div className="flex flex-col gap-5">
        {canSubmit ? <TakeComposer post={post} displayName={displayName} avatarUrl={avatarUrl} /> : null}
        {!canSubmit && !post.viewerAnswered && viewerCanAnswer ? (
          <p className="border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">You did not make picks for this prompt.</p>
        ) : null}

        {youComment ? (
          <TakeCard
            comment={youComment}
            isYou
            avatarUrl={avatarUrl}
            commentHref={viewerTake ? `/prompts/${post.id}/takes/${viewerTake.id}` : undefined}
            footer={
              <span className="flex items-center gap-3 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">
                Picks locked in
                {points !== null ? (
                  <span className={`grade-scoremark grade-scoremark--standings ${points > 0 ? "grade-scoremark--elite" : "grade-scoremark--rough"}`}>+{points}</span>
                ) : null}
              </span>
            }
          >
            {isPicksPost(post) ? (
              <YourCalls slots={post.slots} responses={post.viewerResponse ?? {}} />
            ) : post.templateKind === "power_rankings" ? (
              <div className="px-4 pt-4">
                <PowerRankingsSlot slot={post.slots[0]} disabled showEditorHeader={false} response={post.viewerResponse?.[post.slots[0].id] ?? []} onChange={() => {}} previousRankByTeam={post.previousRankByTeam ?? {}} />
              </div>
            ) : (
              <div className="flex flex-col gap-4 px-4 pt-4">
                {post.slots.map((slot) => (
                  <SlotFaceC key={slot.id} slot={slot} disabled response={post.viewerResponse?.[slot.id] ?? []} onChange={() => {}} allResponses={post.viewerResponse ?? {}} />
                ))}
              </div>
            )}
          </TakeCard>
        ) : null}

        {youComment && (isPicksPost(post) || post.templateKind === "power_rankings") ? (
          <ShareTakeButton post={post} responses={post.viewerResponse ?? {}} />
        ) : null}

        {(post.viewerAnswered || !viewerCanAnswer) && otherTakes.length ? (
          <div className="flex flex-col gap-3" aria-label="Other takes">
            <h2 className="px-1 font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">Other takes</h2>
            {otherTakes.map((take) => (
              <TakeCard
                key={take.id}
                comment={take}
                commentHref={`/prompts/${post.id}/takes/${take.id}`}
                collapsedByDefault={Boolean(isPicksPost(post) && take.response)}
              >
                {isPicksPost(post) && take.response ? (
                  <YourCalls slots={post.slots} responses={take.response} collapsible />
                ) : null}
              </TakeCard>
            ))}
          </div>
        ) : null}
      </div>
    </section>
  );
}
