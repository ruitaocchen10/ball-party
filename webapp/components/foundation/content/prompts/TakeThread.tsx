"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { postComment } from "@/lib/foundation/content/prompts/client";
import { createClient } from "@/lib/supabase/client";
import { TakeReplyComposer } from "./TakeReplyComposer";
import { YourCalls } from "./SlotFaces";
import { TakeCard } from "./TakeCard";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";

/** The focused discussion screen for one take and its one-level reply thread. */
export function TakeThread({
  post,
  take,
  displayName,
  avatarUrl,
  viewerCanAnswer = true,
}: {
  post: Post;
  take: Comment;
  displayName: string;
  avatarUrl: string | null;
  viewerCanAnswer?: boolean;
}) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const [body, setBody] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const takeResponse = take.response ?? (take.isViewer ? post.viewerResponse : undefined);

  async function submit() {
    const trimmed = body.trim();
    if (!trimmed || pending) return;

    setPending(true);
    setError(null);
    const result = await postComment(clientRef.current ?? (clientRef.current = createClient()), {
      postId: post.id,
      body: trimmed,
      parentCommentId: take.id,
    });
    setPending(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    setBody("");
    router.refresh();
  }

  return (
    <section aria-label={`Discussion for ${take.author}'s take`} className="mt-5 w-full max-w-[760px] pb-16">
      <TakeCard
        comment={take}
        isYou={take.isViewer}
        avatarUrl={take.isViewer ? avatarUrl : null}
        commentHref={`#take-comment-${take.id}`}
        collapsedByDefault={Boolean(isPicksPost(post) && takeResponse)}
        composer={viewerCanAnswer ? (
          <TakeReplyComposer
            takeId={take.id}
            displayName={displayName}
            avatarUrl={avatarUrl}
            body={body}
            pending={pending}
            error={error}
            onBodyChange={setBody}
            onSubmit={submit}
          />
        ) : undefined}
        thread={
          <div>
            {take.replies.length ? (
              <div className="flex flex-col">
                {take.replies.map((reply) => (
                  <TakeCard key={reply.id} comment={reply} isYou={reply.isViewer} avatarUrl={reply.isViewer ? avatarUrl : null} />
                ))}
              </div>
            ) : (
              <p className="px-4 py-5 text-sm text-fg-muted">Be the first to add a comment.</p>
            )}
          </div>
        }
      >
        {isPicksPost(post) && takeResponse ? (
          <YourCalls slots={post.slots} responses={takeResponse} collapsible />
        ) : null}
      </TakeCard>


    </section>
  );
}
