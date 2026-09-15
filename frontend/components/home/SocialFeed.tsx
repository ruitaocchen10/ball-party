import Link from "next/link";

import { HuddleHeading, PromptFeedShell } from "@/components/foundation/content/prompts/PromptFeedShell";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";

/** Home is the Huddle's canonical home, using the shared prompt interaction rather than a second preview-only feed. */
export function SocialFeed({ posts, signedIn, canAnswer, gameContexts }: { posts: Post[]; signedIn: boolean; canAnswer: boolean; gameContexts: MatchupGameContext[] }) {
  return (
    <section aria-label="Huddle">
      {signedIn ? (
        posts.length ? (
          <PromptFeedShell initialPosts={posts} canAnswer={canAnswer} gameContexts={gameContexts} home />
        ) : (
          <><HuddleHeading /><EmptyFeed /></>
        )
      ) : (
        <><HuddleHeading /><SignInFeed /></>
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

function SignInFeed() {
  return (
    <div className="mt-5 border border-dashed border-line bg-surface-raised px-5 py-9 text-center">
      <p className="font-slab text-2xl uppercase">Join the huddle</p>
      <p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-fg-muted">Sign in to see the week&apos;s picks and add your voice.</p>
      <Link href="/login?next=/" className="mt-5 inline-flex bg-panel px-4 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">Sign in</Link>
    </div>
  );
}
