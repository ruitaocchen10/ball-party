import Link from "next/link";

/**
 * The prompt a take answers, drawn as a quoted strip ahead of the take and
 * linking to the prompt. Without a `postId` it is a plain, unlinked strip.
 */
export function TakePromptStrip({ postId, caption }: { postId: string | null; caption: string }) {
  if (!postId) {
    return <p className="rounded-card border border-line bg-surface px-3 py-2 text-[15px] leading-5 text-fg-muted">{caption}</p>;
  }
  return (
    <Link
      href={`/prompts/${postId}`}
      className="block rounded-card border border-line bg-surface px-3 py-2 transition-colors hover:border-fg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
    >
      <span className="block type-label-xs text-fg-muted">Answering</span>
      <span className="mt-0.5 line-clamp-2 block text-[15px] leading-5 font-medium text-fg">{caption}</span>
    </Link>
  );
}
