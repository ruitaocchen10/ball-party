"use client";

import { useRouter } from "next/navigation";

import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";
import { PromptPostFeed } from "./PromptPostUI";

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
  return <><PageHeader eyebrow="Social" title="The huddle" /><PromptPostFeed posts={initialPosts} viewerCanAnswer={canAnswer} onSelectPost={(postId) => router.push(`/prompts/${postId}`)} gameContexts={gameContexts} home={home} /></>;
}
