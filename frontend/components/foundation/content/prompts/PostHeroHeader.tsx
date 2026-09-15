import { ArrowLeft } from "lucide-react";
import Link from "next/link";

import type { Post } from "@/lib/foundation/content/prompts/types";

type PostHeroHeaderProps = {
  post: Post;
};

/**
 * The detail-page heading deliberately shares the Huddle feed's column,
 * type scale, and divider. Opening a prompt should feel like focusing an item
 * in that feed, not entering a separate full-bleed experience.
 */
export function PostHeroHeader({ post }: PostHeroHeaderProps) {
  return (
    <header className="w-full max-w-[760px] border-b border-line pb-4">
      <p className="font-mono text-[10px] font-semibold tracking-[0.16em] text-hidden-text uppercase">Social</p>
      <div className="mt-1 flex items-start justify-between gap-4">
        <h1 className="font-slab text-[34px] leading-none uppercase sm:text-[42px]">{post.promptText}</h1>
        <Link
          href="/"
          className="mt-1 inline-flex shrink-0 items-center gap-1 border-b border-fg/50 pb-1 font-mono text-[10px] tracking-[0.12em] text-fg uppercase transition-colors hover:border-fg hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-panel"
        >
          <ArrowLeft className="h-3.5 w-3.5" strokeWidth={2.25} />
          Huddle
        </Link>
      </div>
      <p className="mt-3 max-w-2xl text-sm leading-5 text-fg-muted">{post.caption}</p>
    </header>
  );
}
