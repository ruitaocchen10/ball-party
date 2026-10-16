"use client";

import { useRouter } from "next/navigation";
import { useCallback, useRef } from "react";

import { createPromptPost } from "@/lib/foundation/content/prompts/client";
import type { NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { createClient } from "@/lib/supabase/client";
import { easternDate, linkScheduleSlot, markScheduleReady, saveScheduleDraft } from "@/lib/foundation/content/prompts/schedule";
import { PromptPostComposer, type ComposerSlot, type CreatePromptPostParams, type SaveDraftParams } from "./PromptPostUI";
import type { Player } from "@/lib/foundation/content/prompts/types";

/**
 * The admin-only surface that actually creates prompts — nothing in the
 * public nav links here, and nothing on Home can reach it. Auth gating
 * lives once in app/admin/layout.tsx; this only has to place the write,
 * which prompts.create_post (0095) re-checks server-side
 * (prompts_private.is_admin()) regardless of the page guard.
 */
export function PromptComposerShell({ displayName, games, players, slot }: { displayName: string; games: NflScheduleGame[]; players: Player[]; slot?: ComposerSlot }) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);

  async function publish(params: CreatePromptPostParams) {
    const result = await createPromptPost(getClient(), params);
    if ("id" in result && params.schedule) {
      await linkScheduleSlot(getClient(), result.id, { kind: params.templateKind, ...params.schedule });
    }
    return result;
  }

  // Composing into a calendar slot (BPP-15): the draft is stored on the slot
  // and the database opens it later, through the same create_post.
  async function saveDraft({ post, composer, opensAt, lockAt }: SaveDraftParams) {
    return saveScheduleDraft(getClient(), slot!.id, { post, composer, opensAt, lockAt });
  }

  async function markReady() {
    return markScheduleReady(getClient(), slot!.id);
  }

  return (
    <PromptPostComposer
      displayName={displayName}
      games={games}
      players={players}
      onPublish={publish}
      slot={slot}
      onSaveDraft={slot ? saveDraft : undefined}
      onMarkReady={slot ? markReady : undefined}
      onScheduled={slot ? (opensAt) => router.push(`/admin?start=${easternDate(opensAt)}`) : undefined}
    />
  );
}
