"use client";

import { useContext } from "react";

import { SearchQueryContext } from "@/components/home/search-context";
import { SocialFeed } from "@/components/home/SocialFeed";
import { matchesSearchQuery } from "@/lib/foundation/content/prompts/logic";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";

/**
 * SocialFeed, filtered live by SearchQueryProvider's query as the viewer
 * types — no Enter, no round trip. `posts` is always the full, unfiltered
 * list; the empty state (SocialFeed's EmptyFeed) is what a no-match search
 * falls through to, giving "no jets posts" its immediate feedback.
 */
export function HuddleFeed({ posts, canAnswer, gameContexts }: { posts: Post[]; canAnswer: boolean; gameContexts: MatchupGameContext[] }) {
  const search = useContext(SearchQueryContext);
  const visiblePosts = search ? posts.filter((post) => matchesSearchQuery(post, search.query)) : posts;

  return <SocialFeed posts={visiblePosts} canAnswer={canAnswer} gameContexts={gameContexts} />;
}
