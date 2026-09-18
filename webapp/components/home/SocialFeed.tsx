import { PromptFeedShell } from "@/components/foundation/content/prompts/PromptFeedShell";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";

/** Home is the Huddle's canonical home, using the shared prompt interaction rather than a second preview-only feed. */
export function SocialFeed({ posts, canAnswer, gameContexts }: { posts: Post[]; canAnswer: boolean; gameContexts: MatchupGameContext[] }) {
  return (
    <section aria-label="Huddle">
      {posts.length ? (
        <PromptFeedShell initialPosts={posts} canAnswer={canAnswer} gameContexts={gameContexts} home />
      ) : (
        <><PageHeader eyebrow="Social" title="The huddle" /><EmptyFeed /></>
      )}
    </section>
  );
}

function EmptyFeed() {
  return (
    <div className="mt-5 border border-dashed border-line bg-surface-raised px-5 py-9 text-center">
      <p className="font-slab text-2xl uppercase">The huddle is quiet</p>
      <p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-fg-muted">New weekly picks will show up here.</p>
    </div>
  );
}
