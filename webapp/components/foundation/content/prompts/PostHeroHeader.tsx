import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import type { Post } from "@/lib/foundation/content/prompts/types";

type PostHeroHeaderProps = {
  post: Post;
  /** The contextual route out of this detail view. */
  backHref?: string;
  backLabel?: string;
};

/**
 * The detail-page heading deliberately shares the Huddle feed's column,
 * type scale, and divider. Opening a prompt should feel like focusing an item
 * in that feed, not entering a separate full-bleed experience.
 */
export function PostHeroHeader({
  post,
  backHref = "/",
  backLabel = "Huddle",
}: PostHeroHeaderProps) {
  return (
    <PageHeader
      backHref={backHref}
      backLabel={backLabel}
      eyebrow="Social"
      title={post.promptText}
      description={post.caption}
    />
  );
}
