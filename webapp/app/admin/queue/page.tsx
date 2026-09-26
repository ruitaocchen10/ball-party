import Link from "next/link";

/**
 * Nothing to review yet — there's no pipeline proposing prompt drafts to
 * approve/edit here. Compose is still the only way a prompt gets written.
 * This fills in once a data feed exists to draft from; an honest empty state
 * until then, not a mock of one.
 */
export default function AdminQueuePage() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Queue</h1>
      <p className="mt-2 max-w-[60ch] text-sm text-fg-muted">
        Drafts waiting for your review. Nothing goes live until you approve it.
      </p>

      <div className="mt-8 border border-dashed border-line px-6 py-16 text-center">
        <h2 className="font-slab text-2xl leading-none uppercase">Nothing to review</h2>
        <p className="mx-auto mt-3 max-w-[46ch] text-sm text-fg-muted">
          Drafts proposed from a data feed will show up here once one is connected. Until then, every
          prompt is written straight from Compose.
        </p>
        <Link
          href="/admin/prompts"
          className="mt-6 inline-block border border-fg bg-fg px-4 py-2.5 font-mono text-[10px] font-bold tracking-[0.12em] text-surface uppercase transition-colors hover:bg-white"
        >
          Write a prompt →
        </Link>
      </div>
    </div>
  );
}
