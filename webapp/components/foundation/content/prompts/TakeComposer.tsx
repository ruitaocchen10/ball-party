"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { Button } from "@/components/foundation/ui-kit/Button";
import { submitPromptResponse } from "@/lib/foundation/content/prompts/client";
import { createClient } from "@/lib/supabase/client";
import { AuthorIdentity } from "./AuthorIdentity";
import { GamePickFace, GamePickList, PowerRankingsSlot, SlotFaceC } from "./SlotFaces";
import { WeeklyAwardsSlots } from "./WeeklyAwards";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import type { Post } from "@/lib/foundation/content/prompts/types";
import { Badge } from "@/components/foundation/ui-kit/Badge";

type TakeComposerProps = {
  post: Post;
  displayName: string;
  avatarUrl: string | null;
};

/**
 * The pre-answer input surface — profile row, an optional take, the pick
 * inputs, and Lock in. It uses the TakeCard shell so composing a take feels
 * like the card it becomes after submission.
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
    if (post.templateKind === "power_rankings") return response.length === 5 || response.length === 10 || response.length === 32;
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

  return (
    <section aria-label="Make your picks" className="flex flex-col">
      <div className="relative flex flex-1 flex-col overflow-hidden border border-line bg-surface-raised text-fg shadow-[0_10px_24px_rgb(0_0_0/0.4)]">
        <div className="flex items-center gap-2.5 px-4 pt-4">
          <AuthorIdentity name={displayName} avatarUrl={avatarUrl} />
          <Badge>You</Badge>
        </div>
        <div className="px-4 pt-4">
          <label htmlFor={`prompt-take-${post.id}`} className="type-label text-fg-muted">
            Add a take <span className="normal-case">(optional)</span>
          </label>
          <textarea
            id={`prompt-take-${post.id}`}
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            maxLength={280}
            rows={2}
            placeholder="Share your reasoning…"
            className="mt-2 block w-full resize-none border border-line bg-surface px-3 py-2 text-lg leading-6 text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none"
          />
        </div>
        {isPicksPost(post) && post.slots.length === 1 ? (
          <GamePickFace slot={post.slots[0]} disabled={false} response={draft[post.slots[0].id] ?? []} onChange={(response) => setSlotResponse(post.slots[0].id, response)} />
        ) : isPicksPost(post) ? (
          <GamePickList slots={post.slots} responses={draft} onChange={setSlotResponse} />
        ) : post.templateKind === "weekly_awards" ? (
          <WeeklyAwardsSlots slots={post.slots} responses={draft} onChange={setSlotResponse} />
        ) : post.templateKind === "power_rankings" ? (
          <div className="px-4 pt-4">
            <PowerRankingsSlot
              slot={post.slots[0]}
              response={draft[post.slots[0].id] ?? []}
              onChange={(response) => setSlotResponse(post.slots[0].id, response)}
              previousRankByTeam={post.previousRankByTeam ?? {}}
            />
          </div>
        ) : (
          <div className="flex flex-col gap-4 px-4 pt-4">
            {post.slots.map((slot) => (
              <SlotFaceC key={slot.id} slot={slot} disabled={false} response={draft[slot.id] ?? []} onChange={(response) => setSlotResponse(slot.id, response)} allResponses={draft} />
            ))}
          </div>
        )}
        <div className="mt-5 px-4 pb-4">
          <Button variant="solid" fullWidth disabled={!ready || pending} onClick={submitAnswer}>
            {pending ? "Locking in…" : "Lock in"}
          </Button>
        </div>
        {error ? <p role="alert" className="border-t border-line px-4 py-3 type-label text-grade-rough">{error}</p> : null}
      </div>
    </section>
  );
}
