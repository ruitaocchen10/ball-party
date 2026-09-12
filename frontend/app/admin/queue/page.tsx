/**
 * Nothing to review yet — there's no pipeline proposing prompt drafts to
 * approve/edit here. Compose is still the only way a prompt gets written.
 * This fills in once a data feed exists to draft from; an honest empty state
 * until then, not a mock of one.
 */
export default function AdminQueuePage() {
  return (
    <div className="mx-auto w-full max-w-2xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="mb-2 font-slab text-2xl leading-none uppercase">Queue</h1>
      <p className="max-w-[52ch] text-sm text-fg-muted">
        Nothing to review yet — this fills in once a pipeline exists to propose prompt drafts from a
        data feed. For now, every prompt gets written straight from Compose.
      </p>
    </div>
  );
}
