import { Ban, CircleCheck, ClipboardList, Clock, Flag, Lock, Radio } from "lucide-react";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import {
  POST_STATUS_LABELS,
  formatEasternDay,
  formatEasternTime,
  type CalendarGame,
  type CalendarPost,
} from "@/lib/foundation/content/prompts/schedule";

/**
 * The four kinds of thing on the admin calendar, drawn so they read apart at a
 * glance (BPP-15). Shape and weight carry the difference, not red (red is for
 * concealed things and errors):
 *
 *   game      no card: a quiet line of text, background information
 *   planned   dashed outline on the page: not real yet (empty, draft)
 *   ready     solid outline with a light left edge: committed, opens by itself
 *   prompt    a filled panel with a status edge: open, locked, resolved, void,
 *             drawn on the day it locks (a slim reminder marks the day it opened)
 *
 * The class strings live here so the key (CalendarKey) draws the very same
 * thing the calendar does.
 */
export const CARD_BASE = "flex flex-col gap-1.5 rounded-card border p-3";

export const SLOT_STYLES = {
  empty: "border-dashed border-line opacity-70",
  draft: "border-dashed border-fg-muted",
  ready: "border-line border-l-4 border-l-fg bg-surface-raised",
} as const;

export const POST_STYLES: Record<CalendarPost["status"], string> = {
  open: "border-panel-line border-l-4 border-l-grade-elite bg-panel text-panel-fg",
  locked: "border-panel-line border-l-4 border-l-panel-muted bg-panel text-panel-fg",
  resolved: "border-panel-line border-l-4 border-l-panel-line bg-panel text-panel-fg opacity-60",
  void: "border-panel-line border-l-4 border-l-panel-line bg-panel text-panel-muted line-through opacity-60",
};

const ICON = "h-3.5 w-3.5 shrink-0";

const POST_ICONS: Record<CalendarPost["status"], typeof Radio> = {
  open: Radio,
  locked: Lock,
  resolved: CircleCheck,
  void: Ban,
};

/** nflverse team codes are already the short names people read ("BUF @ KC"). */
function matchup(game: Pick<CalendarGame, "away" | "home">) {
  return `${game.away} @ ${game.home}`;
}

/** One NFL game: kickoff and matchup, no card. */
export function GameRow({ game }: { game: CalendarGame }) {
  return (
    <span className="flex flex-wrap items-center gap-x-1.5 px-1 py-0.5 type-label text-fg-muted">
      <Flag aria-hidden className={ICON} />
      <span className="whitespace-nowrap">{formatEasternTime(game.kickoff)}</span>
      <span className="whitespace-nowrap text-fg">{matchup(game)}</span>
      {game.primetime ? <span className="type-label-xs text-fg">Prime</span> : null}
    </span>
  );
}

/** Month view folds a day's games into one line; the week view lists them. */
export function GamesSummary({ games }: { games: CalendarGame[] }) {
  const prime = games.filter((game) => game.primetime).length;
  return (
    <span className="flex items-center gap-1.5 px-1 py-0.5 type-label text-fg-muted">
      <Flag aria-hidden className={ICON} />
      <span className="text-fg">{games.length} game{games.length === 1 ? "" : "s"}</span>
      {prime ? <span className="type-label-xs text-fg">{prime} prime</span> : null}
    </span>
  );
}

/** A published prompt, drawn on the day it locks. */
export function PostCard({ post, compact = true }: { post: CalendarPost; compact?: boolean }) {
  const Icon = POST_ICONS[post.status];
  return (
    <span className={`${CARD_BASE} ${POST_STYLES[post.status]}`}>
      <span className="flex items-start justify-between gap-2">
        <span className={`flex items-start gap-1.5 font-slab leading-tight uppercase ${compact ? "text-base" : "text-lg"}`}>
          <Icon aria-hidden className={`${ICON} mt-0.5`} />
          <span className="line-clamp-2">{post.prompt_text}</span>
        </span>
        <Badge tone="muted" size="xs">{POST_STATUS_LABELS[post.status]}</Badge>
      </span>
      <span className="type-label-xs text-panel-muted">{post.template_name}</span>
      <span className="type-label text-panel-muted">
        Locks {formatEasternTime(post.lock_at)} · opened {formatEasternDay(post.created_at)} {formatEasternTime(post.created_at)}
      </span>
    </span>
  );
}

/** The same prompt again on the day it opened, when that is not the day it locks: slimmer, so it reads as a reminder and not a second prompt. */
export function OpenEcho({ post }: { post: CalendarPost }) {
  return (
    <span className="flex items-center gap-1.5 rounded-card border border-dashed border-line px-2 py-1 type-label text-fg-muted">
      <Radio aria-hidden className={ICON} />
      <span className="shrink-0">Opened {formatEasternTime(post.created_at)}</span>
      <span className="truncate text-fg">{post.prompt_text}</span>
    </span>
  );
}

/** A small swatch drawn with the real styles, for the key. */
function Swatch({ className, children }: { className: string; children?: React.ReactNode }) {
  return <span className={`inline-flex h-6 w-9 shrink-0 items-center justify-center rounded-chip border ${className}`}>{children}</span>;
}

/**
 * A quick reference for what each look on the calendar means. Built from the
 * same style strings the calendar uses, so it cannot drift from it.
 */
export function CalendarKey() {
  const items: { swatch: React.ReactNode; title: string; text: string }[] = [
    {
      swatch: <Flag aria-hidden className={`${ICON} text-fg-muted`} />,
      title: "NFL game",
      text: "Kickoff time and matchup. Plain text, not a prompt.",
    },
    {
      swatch: <Swatch className={SLOT_STYLES.empty}><ClipboardList aria-hidden className={ICON} /></Swatch>,
      title: "Empty slot",
      text: "Dashed and faint: a slot waiting for a prompt.",
    },
    {
      swatch: <Swatch className={SLOT_STYLES.draft}><ClipboardList aria-hidden className={ICON} /></Swatch>,
      title: "Draft",
      text: "Dashed: written, but not queued to open.",
    },
    {
      swatch: <Swatch className={`${SLOT_STYLES.ready} border-l-4`}><Clock aria-hidden className={ICON} /></Swatch>,
      title: "Ready",
      text: "Solid with a light edge: opens by itself at its time.",
    },
    {
      swatch: <Swatch className={POST_STYLES.open}><Radio aria-hidden className={ICON} /></Swatch>,
      title: "Open",
      text: "Filled with a green edge: live, players can answer.",
    },
    {
      swatch: <Swatch className={POST_STYLES.locked}><Lock aria-hidden className={ICON} /></Swatch>,
      title: "Locked",
      text: "Filled with a grey edge: answers closed, waiting on the result.",
    },
    {
      swatch: <Swatch className={POST_STYLES.resolved}><CircleCheck aria-hidden className={ICON} /></Swatch>,
      title: "Resolved or void",
      text: "Filled and faded: finished.",
    },
    {
      swatch: <Swatch className="border-dashed border-line text-fg-muted"><Radio aria-hidden className={ICON} /></Swatch>,
      title: "Opened earlier",
      text: "A slim dashed line on the day a prompt opened, when it locks on a later day.",
    },
  ];
  return (
    <details open className="rounded-card border border-line">
      <summary className="cursor-pointer px-3 py-2 type-label-lg text-fg-muted">Key</summary>
      <ul className="grid gap-x-6 gap-y-2 border-t border-line p-3 sm:grid-cols-2 xl:grid-cols-4">
        {items.map((item) => (
          <li key={item.title} className="flex items-start gap-2.5">
            <span className="flex w-9 shrink-0 justify-center pt-0.5">{item.swatch}</span>
            <span className="min-w-0 text-sm leading-5">
              <span className="block font-semibold">{item.title}</span>
              <span className="text-fg-muted">{item.text}</span>
            </span>
          </li>
        ))}
      </ul>
      <p className="border-t border-line px-3 py-2 text-sm text-fg-muted">
        <span className="text-hidden-text">Red text</span> means a prompt needs attention: it is due soon and a step is missing.
      </p>
    </details>
  );
}
