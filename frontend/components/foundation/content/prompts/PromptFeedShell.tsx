"use client";

import { useRouter } from "next/navigation";

import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";
import { PromptPostFeed } from "./PromptPostUI";

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
 * The public Home feed — read and answer only, no compose entry point
 * anywhere on it. See app/admin/prompts/page.tsx for the separate,
 * admin-only surface that actually creates posts.
 *
 * `initialPosts` comes from app/page.tsx's server-side
 * fetchPromptFeed — the database remains the source of truth the same way
 * components/platform/lobbies/LobbyRealtime.tsx documents for the lobby:
 * answering calls prompts.submit_response directly (same idiom as
 * HigherOrLowerMatch's makeCall) and then asks Next to re-render this route
 * from the server rather than hand-patching local state, so the aggregate
 * bars the answer screen hands back to always reflect what the database
 * actually has.
 *
 * Answering has a dedicated, shareable route. The feed remains only a prompt
 * cover; following a card to /prompts/[id] keeps browser history, reloads,
 * and copied links honest.
 */
export function PromptFeedShell({ initialPosts, canAnswer, gameContexts, home = false }: { initialPosts: Post[]; canAnswer: boolean; gameContexts: MatchupGameContext[]; home?: boolean }) {
  const router = useRouter();
  return <><HuddleHeading /><PromptPostFeed posts={initialPosts} viewerCanAnswer={canAnswer} onSelectPost={(postId) => router.push(`/prompts/${postId}`)} gameContexts={gameContexts} home={home} /></>;
}
