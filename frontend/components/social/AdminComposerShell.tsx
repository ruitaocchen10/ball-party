"use client";

import { useCallback, useRef } from "react";

import { createPromptPost } from "@/lib/prompts/client";
import type { NflScheduleGame } from "@/lib/nfl/schedule";
import { createClient } from "@/lib/supabase/client";
import { PromptPostComposer, type CreatePromptPostParams } from "./PromptPostUI";
import type { Player } from "./types";

/**
 * PROTOTYPE UI, REAL DATA. The admin-only surface that actually creates
 * prompts — nothing in the public nav links here, and nothing on Home
 * can reach it. Auth gating lives once in app/admin/layout.tsx; this only
 * has to place the write, which prompts.create_post (0095) re-checks
 * server-side (prompts_private.is_admin()) regardless of the page guard.
 */
export function AdminComposerShell({ displayName, games, players }: { displayName: string; games: NflScheduleGame[]; players: Player[] }) {
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);

  async function publish(params: CreatePromptPostParams) {
    return createPromptPost(getClient(), params);
  }

  return <PromptPostComposer displayName={displayName} games={games} players={players} onPublish={publish} />;
}
