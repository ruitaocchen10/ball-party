import { ScheduleCalendar } from "@/components/admin/ScheduleCalendar";
import { easternDate, prefillSchedule } from "@/lib/foundation/content/prompts/schedule";
import { createClient } from "@/lib/supabase/server";

/**
 * The prompt calendar (BPP-15): a week or a month, each prompt on the day it
 * opens. The slots themselves are made ahead of time by a daily job; asking
 * here as well is idempotent and means a freshly reset database isn't empty.
 * `?start=YYYY-MM-DD` opens on that date (the composer returns to the day a
 * prompt was scheduled for). Auth for /admin/* lives in the layout.
 */
export default async function AdminCalendarPage({ searchParams }: { searchParams: Promise<{ start?: string }> }) {
  const { start } = await searchParams;
  const supabase = await createClient();
  await prefillSchedule(supabase);

  const initialDate = start && /^\d{4}-\d{2}-\d{2}$/.test(start) ? start : easternDate(new Date());

  return (
    <div className="mx-auto w-full max-w-7xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Calendar</h1>
      <p className="mt-2 mb-6 max-w-[60ch] text-sm text-fg-muted">
        A planned prompt sits on the day it should be posted, and a live one on the day it locks, with the NFL games around them. Click a planned prompt to write it; once it&apos;s marked ready it goes live by itself at its time. The key explains each look.
      </p>
      <ScheduleCalendar initialDate={initialDate} />
    </div>
  );
}
