"use client";

import { useRef } from "react";
import { useRouter } from "next/navigation";

import { postComment } from "@/lib/prompts/client";
import { createClient } from "@/lib/supabase/client";
import { SlotFaceC, YourCalls } from "./SlotFaces";
import { TakeCard } from "./TakeCard";
import { TakeComposer } from "./TakeComposer";
import { isPicksPost, totalPoints } from "./logic";
import type { Comment, Post } from "./types";

/**
 * A prompt's detail page, in the same feed column as the Huddle cards: your own take posts at the top —
 * composer before you've answered, an ordinary TakeCard after — then every
 * other take below it, same card, like opening a post and reading its
 * replies. Right column is PromptContext, which now carries what OtherTakes
 * used to duplicate as a second rail of takes.
 */
export function PromptThread({ post, displayName, avatarUrl }: { post: Post; displayName: string; avatarUrl: string | null }) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const canSubmit = post.status === "open" && !post.viewerAnswered;
  const viewerTake = post.comments.find((item) => item.isViewer && item.postedWithPick);
  const otherTakes = post.comments.filter((item) => !(item.isViewer && item.postedWithPick));
  const points = totalPoints(post);

  async function reply(parentId: string, body: string) {
    const result = await postComment(clientRef.current ?? (clientRef.current = createClient()), {
      postId: post.id,
      body,
      parentCommentId: parentId,
    });
    if (!result.error) router.refresh();
    return result;
  }

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
        {!canSubmit && !post.viewerAnswered ? (
          <p className="border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">You did not make picks for this prompt.</p>
        ) : null}

        {youComment ? (
          <TakeCard
            comment={youComment}
            isYou
            avatarUrl={avatarUrl}
            onReply={viewerTake ? (body) => reply(viewerTake.id, body) : undefined}
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
              <YourCalls slots={post.slots} responses={post.viewerResponse ?? {}} resolved={post.status === "resolved"} />
            ) : (
              <div className="flex flex-col gap-4 px-4 pt-4">
                {post.slots.map((slot) => (
                  <SlotFaceC key={slot.id} slot={slot} disabled response={post.viewerResponse?.[slot.id] ?? []} onChange={() => {}} allResponses={post.viewerResponse ?? {}} />
                ))}
              </div>
            )}
          </TakeCard>
        ) : null}

        {otherTakes.length ? (
          <>
            <div className="my-2 flex items-center gap-3" role="separator">
              <span aria-hidden className="h-px flex-1 bg-line" />
              <span className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">
                {otherTakes.length} other {otherTakes.length === 1 ? "take" : "takes"}
              </span>
              <span aria-hidden className="h-px flex-1 bg-line" />
            </div>
            {otherTakes.map((take) => (
              <TakeCard key={take.id} comment={take} onReply={(body) => reply(take.id, body)} collapsedByDefault={Boolean(isPicksPost(post) && take.response)}>
                {isPicksPost(post) && take.response ? (
                  <YourCalls slots={post.slots} responses={take.response} resolved={post.status === "resolved"} collapsible />
                ) : null}
              </TakeCard>
            ))}
          </>
        ) : (
          <p className="border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">No other takes yet. Share this prompt to get the conversation going.</p>
        )}
      </div>
    </section>
  );
}
