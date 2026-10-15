"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { TakeReplyComposer } from "@/components/foundation/content/prompts/TakeReplyComposer";
import { postComment } from "@/lib/foundation/content/prompts/client";
import { timeAgo } from "@/lib/foundation/friends/friends";
import type { ListReply } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/client";

/** The replies under an update card, and the box to add one. Replies hang on the card's note, one level deep. */
export function ListUpdateThread({
  postId,
  takeId,
  replies,
  displayName,
  avatarUrl,
}: {
  postId: string;
  takeId: string | null;
  replies: ListReply[];
  displayName: string;
  avatarUrl: string | null;
}) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const [body, setBody] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    const trimmed = body.trim();
    if (!trimmed || pending || !takeId) return;
    setPending(true);
    setError(null);
    const result = await postComment((clientRef.current ??= createClient()), { postId, body: trimmed, parentCommentId: takeId });
    setPending(false);
    if (result.error) return setError(result.error);
    setBody("");
    router.refresh();
  }

  return (
    <section aria-label="Replies" className="mt-5">
      <h2 className="type-label font-bold text-fg-muted">{replies.length ? `${replies.length} ${replies.length === 1 ? "reply" : "replies"}` : "Replies"}</h2>
      {takeId ? (
        <div className="mt-3 rounded-card border border-line bg-surface-raised p-3">
          <TakeReplyComposer takeId={takeId} displayName={displayName} avatarUrl={avatarUrl} body={body} pending={pending} error={error} onBodyChange={setBody} onSubmit={submit} />
        </div>
      ) : null}
      {replies.length ? (
        <ul className="mt-4 flex flex-col gap-4">
          {replies.map((reply) => (
            <li key={reply.id} className="flex gap-3">
              <AuthorAvatar name={reply.authorName} avatarUrl={reply.avatarUrl} className="h-8 w-8" />
              <div className="min-w-0">
                <p className="type-label text-fg-muted">
                  <span className="font-bold text-fg">{reply.isViewer ? "You" : reply.authorName}</span> · {timeAgo(reply.createdAt)}
                </p>
                <p className="mt-1 text-[15px] leading-6 text-fg">{reply.body}</p>
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 text-sm text-fg-muted">No replies yet.</p>
      )}
    </section>
  );
}
