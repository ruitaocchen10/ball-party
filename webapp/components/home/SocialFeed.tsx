import { PromptFeedShell } from "@/components/foundation/content/prompts/PromptFeedShell";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";

/** Home is the Huddle's canonical home, using the shared prompt interaction rather than a second preview-only feed. */
export function SocialFeed({ posts, canAnswer, gameContexts }: { posts: Post[]; canAnswer: boolean; gameContexts: MatchupGameContext[] }) {
  return (
    <section aria-label="Huddle">
      {posts.length ? (
        <PromptFeedShell initialPosts={posts} canAnswer={canAnswer} gameContexts={gameContexts} home />
      ) : (
        <EmptyFeed />
      )}
    </section>
  );
}

function EmptyFeed() {
  return (
    <EmptyState title="The huddle is quiet" className="mt-5">
      New weekly picks will show up here.
    </EmptyState>
  );
}
