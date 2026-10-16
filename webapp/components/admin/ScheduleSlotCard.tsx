import { ClipboardList, Clock } from "lucide-react";
import Link from "next/link";

import { CARD_BASE, SLOT_STYLES } from "@/components/admin/CalendarCards";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import {
  SLOT_KIND_LABELS,
  SLOT_STATE_LABELS,
  composeHref,
  formatEastern,
  formatEasternTime,
  type ScheduleSlot,
  type SlotDisplayState,
} from "@/lib/foundation/content/prompts/schedule";

const STATE_TONES: Record<SlotDisplayState, "muted" | "outline" | "soft" | "solid" | "success"> = {
  empty: "muted",
  draft: "outline",
  ready: "soft",
  live: "success",
  locked: "solid",
  resolved: "solid",
  void: "muted",
  removed: "muted",
};

/** nflverse ids read season_week_away_home: "2026_05_BUF_KC" is BUF at KC. */
export function slotTitle(slot: Pick<ScheduleSlot, "kind" | "game_id">): string {
  if (slot.game_id) {
    const [, , away, home] = slot.game_id.split("_");
    if (away && home) return `${away} @ ${home}`;
  }
  return SLOT_KIND_LABELS[slot.kind];
}

/** Where a slot leads: the composer, or Posts once it has gone live. */
export function slotHref(slot: Pick<ScheduleSlot, "id" | "state">): string {
  return slot.state === "published" ? "/admin/posts" : composeHref(slot.id);
}

/**
 * What a slot says: what it is, its state, when it opens, and, if it is due
 * soon but not ready, the manual step still missing. The calendar draws this
 * inside its own event element; the queue wraps it in a link (ScheduleSlotCard).
 *
 * `compact` is the calendar's form: the day is the cell it sits in, so only the
 * time is written. Its look follows its state (see CalendarCards): empty and
 * draft are dashed, since they are not real yet, and ready is solid with a
 * light edge. A slot with no open time yet sits on its lock day as a placeholder.
 */
export function ScheduleSlotSummary({ slot, showWeek = false, compact = false }: { slot: ScheduleSlot; showWeek?: boolean; compact?: boolean }) {
  const style = slot.state === "ready" ? SLOT_STYLES.ready : slot.state === "draft" ? SLOT_STYLES.draft : SLOT_STYLES.empty;
  const Icon = slot.state === "ready" ? Clock : ClipboardList;
  return (
    <span className={`${CARD_BASE} ${style}`}>
      <span className="flex items-start justify-between gap-2">
        <span className={`flex items-start gap-1.5 font-slab leading-none uppercase ${compact ? "text-base" : "text-lg"}`}>
          <Icon aria-hidden className="h-3.5 w-3.5 shrink-0" />
          {slotTitle(slot)}
        </span>
        <Badge tone={STATE_TONES[slot.display_state]} size="xs">{SLOT_STATE_LABELS[slot.display_state]}</Badge>
      </span>
      {compact && slot.game_id ? <span className="type-label-xs text-fg-muted">{SLOT_KIND_LABELS[slot.kind]}</span> : null}
      {showWeek ? <span className="type-label text-fg-muted">{SLOT_KIND_LABELS[slot.kind]} · Week {slot.week}</span> : null}
      {slot.caption && slot.has_draft ? <span className="truncate text-sm text-fg-muted">{slot.caption}</span> : null}
      <span className="type-label text-fg-muted">
        {compact
          ? slot.opens_at
            ? `Opens ${formatEasternTime(slot.opens_at)} · locks ${formatEastern(slot.lock_at)}`
            : `Not scheduled · locks ${formatEasternTime(slot.lock_at)}`
          : `${slot.opens_at ? `Opens ${formatEastern(slot.opens_at)}` : "No open time"} · Locks ${formatEastern(slot.lock_at)}`}
      </span>
      {slot.needs_attention ? (
        <span className="flex flex-col gap-1">
          <Badge tone="solid" size="xs" className="self-start">Needs attention</Badge>
          {slot.attention ? <span className="text-sm text-hidden-text">{slot.attention}</span> : null}
        </span>
      ) : null}
    </span>
  );
}

/** A slot as a link, for lists (the queue). */
export function ScheduleSlotCard({ slot, showWeek = false }: { slot: ScheduleSlot; showWeek?: boolean }) {
  return (
    <Link href={slotHref(slot)} className="block transition-colors [&>span]:hover:border-fg">
      <ScheduleSlotSummary slot={slot} showWeek={showWeek} />
    </Link>
  );
}
