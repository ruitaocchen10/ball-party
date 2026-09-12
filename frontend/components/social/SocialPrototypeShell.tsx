"use client";

import { useCallback, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { submitPromptResponse } from "@/lib/prompts/client";
import { createClient } from "@/lib/supabase/client";
import { PostAnswerScreen } from "./PostAnswerScreen";
import type { MatchupGameContext, Post } from "./types";
import { VariantCFeed } from "./VariantC";

/** Shown only with the feed; a selected prompt is a focused detail view. */
export function HuddleHeading() {
  return (
    <div className="w-full max-w-[760px] border-b border-line pb-4">
      <p className="font-mono text-[10px] font-semibold tracking-[0.16em] text-hidden-text uppercase">Social</p>
      <h1 id="feed-heading" className="mt-1 font-slab text-[34px] leading-none uppercase sm:text-[42px]">The huddle</h1>
    </div>
  );
}

/**
 * PROTOTYPE UI, REAL DATA. The public Home feed — read and answer only,
 * no compose entry point anywhere on it. See app/admin/prompts/page.tsx for
 * the separate, admin-only surface that actually creates posts.
 *
 * `initialPosts` comes from app/page.tsx's server-side
 * fetchPromptFeed — the database remains the source of truth the same way
 * components/lobby/LobbyRealtime.tsx documents for the lobby: answering
 * calls prompts.submit_response directly (same idiom as HigherOrLowerMatch's
 * makeCall) and then asks Next to re-render this route from the server
 * rather than hand-patching local state, so the aggregate bars the answer
 * screen hands back to always reflect what the database actually has.
 *
 * Answering is a dedicated screen (PostAnswerScreen), not something done
 * inline in the feed — selectedPostId drives a plain whole-screen swap
 * between the feed and that screen, mirroring the one "focused step, then
 * back" convention already in this app (see AuctionMatch/SabotageDraftMatch,
 * which branch a top-level phase value the same way). No modal, no route.
 */
export function SocialPrototypeShell({ initialPosts, canAnswer, displayName, avatarUrl, gameContexts, home = false }: { initialPosts: Post[]; canAnswer: boolean; displayName: string; avatarUrl: string | null; gameContexts: MatchupGameContext[]; home?: boolean }) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);

  const [selectedPostId, setSelectedPostId] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedPost = selectedPostId ? (initialPosts.find((p) => p.id === selectedPostId) ?? null) : null;

  if (selectedPost) {
    return (
      <PostAnswerScreen
        post={selectedPost}
        displayName={displayName}
        avatarUrl={avatarUrl}
        pending={pending}
        error={error}
        onBack={() => {
          setSelectedPostId(null);
          setError(null);
        }}
        onAnswer={async (response, comment) => {
          setPending(true);
          setError(null);
          const { error } = await submitPromptResponse(getClient(), { postId: selectedPost.id, choices: response, comment });
          setPending(false);
          if (error) {
            setError(error);
            return;
          }
          setSelectedPostId(null);
          router.refresh();
        }}
      />
    );
  }

  return <><HuddleHeading /><VariantCFeed posts={initialPosts} viewerCanAnswer={canAnswer} onSelectPost={setSelectedPostId} gameContexts={gameContexts} home={home} /></>;
}
