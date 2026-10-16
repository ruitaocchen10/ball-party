import Link from "next/link";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Card } from "@/components/foundation/ui-kit/Card";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import {
  LEADERBOARD_SCOPES,
  LEADERBOARD_SCOPE_LABEL,
  type LeaderboardScope,
} from "@/lib/foundation/content/leaderboard/windows";

const FOCUS = "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg";
const LINK_FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg";

/** One row of any board. `detail` is the optional narrow-hidden column (picks, games), `value` the ranked number. */
export type BoardRow = {
  rank: number;
  profileId: string;
  displayName: string;
  avatarUrl: string | null;
  /** When present the row links to /u/<username>; absent or null means "not tappable". */
  username?: string | null;
  isMe: boolean;
  detail?: string;
  value: string;
};

const ROW_GRID_WITH_DETAIL =
  "grid grid-cols-[2.75rem_minmax(0,1fr)_auto] items-center gap-3 sm:grid-cols-[3.5rem_minmax(0,1fr)_5rem_6rem] sm:gap-4";
const ROW_GRID_VALUE_ONLY = "grid grid-cols-[2.75rem_minmax(0,1fr)_auto] items-center gap-3 sm:grid-cols-[3.5rem_minmax(0,1fr)_6rem] sm:gap-4";

/** Friends / Everyone as a pill toggle, the same look as the profile's Ball knower / Gamer toggle. */
export function ScopeToggle({ scope, hrefFor }: { scope: LeaderboardScope; hrefFor: (scope: LeaderboardScope) => string }) {
  return (
    <nav aria-label="Leaderboard scope" className="inline-flex w-fit shrink-0 rounded-full border border-line bg-surface p-1">
      {(["friends", "all"] as const).map((key) => {
        const active = key === scope;
        return (
          <Link
            key={key}
            href={hrefFor(key)}
            aria-current={active ? "page" : undefined}
            className={`flex min-h-9 items-center rounded-full px-4 type-label font-black transition-colors ${FOCUS} ${active ? "bg-hidden text-white" : "text-fg-muted hover:text-fg"}`}
          >
            {LEADERBOARD_SCOPE_LABEL[key]}
          </Link>
        );
      })}
    </nav>
  );
}

export function ScopeNav({ scope, hrefFor }: { scope: LeaderboardScope; hrefFor: (scope: LeaderboardScope) => string }) {
  return (
    <nav aria-label="Leaderboard scope" className="mb-3 flex overflow-hidden rounded-card border border-line">
      {LEADERBOARD_SCOPES.map((key) => {
        const active = key === scope;
        return (
          <Link
            key={key}
            href={hrefFor(key)}
            aria-current={active ? "page" : undefined}
            className={`flex min-h-10 flex-1 items-center justify-center type-label-lg font-bold transition-colors ${FOCUS} ${
              active ? "bg-hidden text-fg" : "text-fg hover:text-fg-muted"
            }`}
          >
            {LEADERBOARD_SCOPE_LABEL[key]}
          </Link>
        );
      })}
    </nav>
  );
}

/** The caller's own standing, above the list: a "you" row when ranked, the reason when not. */
export function StandingBlock({
  ranked,
  rank,
  detailLine,
  headline,
  detail,
  value,
  secondary,
}: {
  ranked: boolean;
  rank: number | null;
  /** Under "You" when ranked. */
  detailLine: string;
  /** Headline and body of the unranked notice. */
  headline: string;
  detail: string;
  value: string | null;
  secondary?: string;
}) {
  if (!ranked) {
    return (
      <div className="rounded-card bg-surface-raised px-5 py-4 shadow-well">
        <p className="type-label font-semibold text-fg">{headline}</p>
        <p className="mt-1.5 text-[15px] leading-6 text-fg-muted">{detail}</p>
      </div>
    );
  }
  const grid = secondary === undefined ? ROW_GRID_VALUE_ONLY : ROW_GRID_WITH_DETAIL;
  return (
    <Card>
      <div className={`${grid} px-4 py-2.5`}>
        <span className="font-slab text-[24px] leading-none">{rank}</span>
        <span className="min-w-0">
          <span className="block font-semibold">You</span>
          <span className="block type-label-xs text-panel-muted">{detailLine}</span>
        </span>
        {secondary !== undefined ? (
          <span className="hidden text-right font-mono text-[13px] text-panel-muted sm:block">{secondary}</span>
        ) : null}
        <span className="text-right font-slab text-[22px] leading-none">{value}</span>
      </div>
    </Card>
  );
}

/** The ranked list with its header, or the empty state when nobody is on the board. */
export function BoardList({
  rows,
  detailLabel,
  valueLabel,
  empty,
}: {
  rows: BoardRow[];
  detailLabel?: string;
  valueLabel: string;
  empty: { title: string; body: React.ReactNode };
}) {
  if (rows.length === 0) {
    return (
      <EmptyState title={empty.title} className="mt-3">
        {empty.body}
      </EmptyState>
    );
  }
  const grid = detailLabel === undefined ? ROW_GRID_VALUE_ONLY : ROW_GRID_WITH_DETAIL;
  return (
    <div className="mt-3 border-t border-line">
      <div className={`${grid} px-4 py-2.5 type-label-xs text-fg-muted`}>
        <span>Rank</span>
        <span>Player</span>
        {detailLabel !== undefined ? <span className="hidden text-right sm:block">{detailLabel}</span> : null}
        <span className="text-right">{valueLabel}</span>
      </div>
      <ol>
        {rows.map((row) => (
          <li key={row.profileId}>
            <BoardRowView row={row} grid={grid} />
          </li>
        ))}
      </ol>
    </div>
  );
}

function BoardRowView({ row, grid }: { row: BoardRow; grid: string }) {
  const top = row.rank <= 3;
  if (row.isMe) {
    return (
      <div className="rounded-card bg-panel text-panel-fg shadow-card">
        <div className={`${grid} px-4 py-2`}>
          <span className="font-slab text-[24px] leading-none">{row.rank}</span>
          <span className="flex min-w-0 items-center gap-3">
            <AuthorAvatar name={row.displayName} avatarUrl={row.avatarUrl} className="h-8 w-8" />
            <span className="truncate font-semibold">{row.displayName}</span>
            <span className="type-label-xs text-panel-muted">You</span>
          </span>
          {row.detail !== undefined ? (
            <span className="hidden text-right font-mono text-[13px] text-panel-muted sm:block">{row.detail}</span>
          ) : null}
          <span className="text-right font-slab text-[22px] leading-none">{row.value}</span>
        </div>
      </div>
    );
  }
  return (
    <div className={`${grid} border-t border-line px-4 py-2`}>
      <span className={`font-slab leading-none ${top ? "text-[28px] text-fg" : "text-[22px] text-fg-muted"}`}>{row.rank}</span>
      <span className="flex min-w-0 items-center gap-3">
        <AuthorAvatar name={row.displayName} avatarUrl={row.avatarUrl} className="h-8 w-8" />
        {row.username ? (
          <Link href={`/u/${row.username}`} className={`truncate text-base font-medium hover:text-fg-muted ${LINK_FOCUS}`}>
            {row.displayName}
          </Link>
        ) : (
          <span className="truncate text-base font-medium">{row.displayName}</span>
        )}
      </span>
      {row.detail !== undefined ? (
        <span className="hidden text-right font-mono text-[13px] text-fg-muted sm:block">{row.detail}</span>
      ) : null}
      <span className="text-right font-slab text-[22px] leading-none">{row.value}</span>
    </div>
  );
}

/** The empty state for a friends board, which points at the profile Friends tab. */
export function FindFriendsLink() {
  return (
    <Link href="/friends" className={`text-fg underline underline-offset-2 ${LINK_FOCUS}`}>
      Find friends
    </Link>
  );
}
