"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/Button";
import { submitPromptResponse } from "@/lib/prompts/client";
import { createClient } from "@/lib/supabase/client";
import { PlayerPortrait } from "./ProtoImages";
import { GamePickFace, GamePickList, SlotFaceC } from "./SlotFaces";
import { isPicksPost } from "./logic";
import type { Post } from "./types";

type TakeComposerProps = {
  post: Post;
  displayName: string;
  avatarUrl: string | null;
};

/**
 * The pre-answer input surface — profile row, an optional take, the pick
 * inputs, and Lock in. Deliberately not styled like a TakeCard: this is a
 * form, not a post yet. Once submitted, the same take renders as an
 * ordinary TakeCard, first in the thread below it (see PromptThread).
 */
export function TakeComposer({ post, displayName, avatarUrl }: TakeComposerProps) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const [draft, setDraft] = useState<Record<string, string[]>>({});
  const [comment, setComment] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function setSlotResponse(slotId: string, response: string[]) {
    setDraft((previous) => ({ ...previous, [slotId]: response }));
  }

  function slotFilled(slotId: string) {
    const slot = post.slots.find((item) => item.id === slotId)!;
    const response = draft[slotId] ?? [];
    return slot.shape === "pick" ? response.length === 1 : response.length === (slot.pickCount ?? slot.options.length);
  }

  async function submitAnswer() {
    setPending(true);
    setError(null);
    const result = await submitPromptResponse(clientRef.current ?? (clientRef.current = createClient()), {
      postId: post.id,
      choices: draft,
      comment: comment.trim() || undefined,
    });
    setPending(false);
    if (result.error) return setError(result.error);
    router.refresh();
  }

  const completedCount = post.slots.filter((slot) => slotFilled(slot.id)).length;
  const ready = completedCount === post.slots.length;
  const statusLabel = post.slots.length > 1 ? `${completedCount} of ${post.slots.length} picks made` : "Make your call";

  return (
    <section aria-label="Make your picks" className="flex flex-col">
      <div className="flex flex-1 flex-col overflow-hidden bg-surface-raised text-fg shadow-[0_10px_24px_rgb(0_0_0/0.4)]">
        <div className="flex items-center gap-2.5 border-b border-line px-4 py-4">
          <PlayerPortrait name={displayName} headshotUrl={avatarUrl} className="h-9 w-9" />
          <span className="min-w-0 truncate font-semibold">{displayName}</span>
        </div>
        <div className="px-4 pt-4">
          <label htmlFor={`prompt-take-${post.id}`} className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">
            Add a take <span className="normal-case">(optional)</span>
          </label>
          <textarea
            id={`prompt-take-${post.id}`}
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            maxLength={280}
            rows={2}
            placeholder="What do you think?"
            className="mt-2 block w-full resize-none border border-line bg-surface px-3 py-2 text-sm leading-5 text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none"
          />
        </div>
        {isPicksPost(post) && post.slots.length === 1 ? (
          <GamePickFace slot={post.slots[0]} disabled={false} response={draft[post.slots[0].id] ?? []} onChange={(response) => setSlotResponse(post.slots[0].id, response)} />
        ) : isPicksPost(post) ? (
          <GamePickList slots={post.slots} responses={draft} onChange={setSlotResponse} />
        ) : (
          <div className="flex flex-col gap-4 px-4 pt-4">
            {post.slots.map((slot) => (
              <SlotFaceC key={slot.id} slot={slot} disabled={false} response={draft[slot.id] ?? []} onChange={(response) => setSlotResponse(slot.id, response)} allResponses={draft} />
            ))}
          </div>
        )}
        <div className="mt-5 flex items-center gap-3 border-t border-line px-4 py-3">
          <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{statusLabel}</p>
        </div>
      </div>
      <div className="fixed right-0 bottom-0 left-0 z-20 border-t border-line bg-surface px-4 py-3 shadow-[0_-8px_24px_rgb(0_0_0/0.4)] sm:px-6 md:left-[var(--sidebar-w)]">
        <div className="mx-auto w-full max-w-[80rem]">
          {error ? <p role="alert" className="mb-2 font-mono text-[10px] tracking-[0.1em] text-grade-rough uppercase">{error}</p> : null}
          <Button variant="ink" fullWidth disabled={!ready || pending} onClick={submitAnswer}>
            {pending ? "Locking in…" : "Lock in"}
          </Button>
        </div>
      </div>
    </section>
  );
}
