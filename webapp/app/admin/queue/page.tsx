import { QueueActions } from "@/components/admin/QueueActions";
import { ScheduleSlotCard } from "@/components/admin/ScheduleSlotCard";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { fetchScheduleQueue, type ScheduleSlot } from "@/lib/foundation/content/prompts/schedule";
import { createClient } from "@/lib/supabase/server";

/**
 * Everything planned but not yet live (BPP-15): drafts, and ready slots
 * waiting for their open time. Ready ones are listed first by when they open;
 * drafts that are due soon carry the same needs-attention flag as the calendar.
 */
export default async function AdminQueuePage() {
  const supabase = await createClient();
  const slots: ScheduleSlot[] = await fetchScheduleQueue(supabase).catch(() => []);
  const ready = slots.filter((slot) => slot.state === "ready");
  const drafts = slots.filter((slot) => slot.state === "draft");

  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Queue</h1>
      <p className="mt-2 max-w-[60ch] text-sm text-fg-muted">
        Drafts and ready prompts that haven&apos;t opened yet. Nothing goes live until it&apos;s marked ready, and then only at its open time.
      </p>

      {slots.length === 0 ? (
        <EmptyState title="Nothing queued" className="mt-8">
          Open a slot on the calendar and save a draft, and it will wait here.
          <span className="mt-4 block">
            <ButtonLink href="/admin" fullWidth={false} size="sm">Open the calendar →</ButtonLink>
          </span>
        </EmptyState>
      ) : (
        <div className="mt-6 flex flex-col gap-8">
          {[
            { title: "Ready to open", rows: ready },
            { title: "Drafts", rows: drafts },
          ].map(({ title, rows }) =>
            rows.length ? (
              <section key={title} aria-label={title}>
                <h2 className="mb-2 type-label-lg text-fg-muted">{title}</h2>
                <ul className="flex flex-col gap-3">
                  {rows.map((slot) => (
                    <li key={slot.id} className="flex flex-col gap-2 sm:flex-row sm:items-start">
                      <div className="min-w-0 flex-1">
                        <ScheduleSlotCard slot={slot} showWeek />
                      </div>
                      <QueueActions slotId={slot.id} ready={slot.state === "ready"} />
                    </li>
                  ))}
                </ul>
              </section>
            ) : null,
          )}
        </div>
      )}
    </div>
  );
}
