import Link from "next/link";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Card } from "@/components/foundation/ui-kit/Card";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import {
  LEADERBOARD_WINDOW_COPY,
  standingCopy,
  type LeaderboardScope,
  type LeaderboardWindow,
  type Standing,
} from "@/lib/foundation/content/leaderboard/windows";

export type LeaderboardRow = {
  rank: number;
  profileId: string;
  displayName: string;
  avatarUrl: string | null;
  /**
   * When present the row links to /u/<username>. The RPC returns null when
   * either side has blocked the other, and the caller's own row is not linked;
   * absent means "not tappable".
   */
  username?: string | null;
  totalPoints: number;
  scoredPicks: number;
  isMe: boolean;
};

const ROW_GRID = "grid grid-cols-[2.75rem_minmax(0,1fr)_auto] items-center gap-3 sm:grid-cols-[3.5rem_minmax(0,1fr)_5rem_6rem] sm:gap-4";

/**
 * The ranked list for one window. The caller's own standing sits above it, in
 * every state (ranked, unranked, hidden), so it never depends on scrolling to
 * find. A caller who is also on the list is highlighted in place there.
 */
export function BallKnowerLeaderboard({
  window,
  scope = "all",
  rows,
  standing,
}: {
  window: LeaderboardWindow;
  scope?: LeaderboardScope;
  rows: LeaderboardRow[];
  standing: Standing;
}) {
  const copy = LEADERBOARD_WINDOW_COPY[window];

  return (
    <div>

      <div className="mt-4">
        {standing.status === "ranked" ? (
          <Card>
            <YouRow standing={standing} scope={scope} />
          </Card>
        ) : (
          <StandingNotice standing={standing} scope={scope} />
        )}
      </div>

      <div className="mt-6 flex flex-wrap items-baseline justify-between gap-2 type-label text-fg-muted">
        <span>{copy.caption}</span>
        <span>
          {standing.rankedCount.toLocaleString("en-US")} ranked {scope === "friends" ? "on your friends board" : "players"}
        </span>
      </div>

      {rows.length === 0 && scope === "friends" ? (
        <EmptyState title="No friends on the board yet" className="mt-3">
          Add friends to see how you stack up against them. Friends appear after {standing.minPicks} scored picks in this window.{" "}
          <Link href="/friends" className="text-fg underline underline-offset-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg">
            Find friends
          </Link>
        </EmptyState>
      ) : rows.length === 0 ? (
        <EmptyState title="No one is ranked yet" className="mt-3">
          Players appear after {standing.minPicks} scored picks in this window.
        </EmptyState>
      ) : (
        <div className="mt-3 border-t border-line">
          <div className={`${ROW_GRID} px-4 py-2.5 type-label-xs text-fg-muted`}>
            <span>Rank</span>
            <span>Player</span>
            <span className="hidden text-right sm:block">Picks</span>
            <span className="text-right">Points</span>
          </div>
          <ol>
            {rows.map((row) => (
              <li key={row.profileId}>
                <LeaderboardRowView row={row} />
              </li>
            ))}
          </ol>
        </div>
      )}

      <p className="mt-5 text-sm leading-6 text-fg-muted">You need at least {standing.minPicks} scored picks in a window to be ranked.</p>
    </div>
  );
}

function LeaderboardRowView({ row }: { row: LeaderboardRow }) {
  const top = row.rank <= 3;
  if (row.isMe) {
    return (
      <div className="rounded-card bg-panel text-panel-fg shadow-card">
        <div className={`${ROW_GRID} px-4 py-2`}>
          <span className="font-slab text-[24px] leading-none">{row.rank}</span>
          <span className="flex min-w-0 items-center gap-3">
            <AuthorAvatar name={row.displayName} avatarUrl={row.avatarUrl} className="h-8 w-8" />
            <span className="truncate font-semibold">{row.displayName}</span>
            <span className="type-label-xs text-panel-muted">You</span>
          </span>
          <span className="hidden text-right font-mono text-[13px] text-panel-muted sm:block">{row.scoredPicks}</span>
          <span className="text-right font-slab text-[22px] leading-none">{row.totalPoints.toLocaleString("en-US")}</span>
        </div>
      </div>
    );
  }
  return (
    <div className={`${ROW_GRID} border-t border-line px-4 py-2`}>
      <span className={`font-slab leading-none ${top ? "text-[28px] text-fg" : "text-[22px] text-fg-muted"}`}>{row.rank}</span>
      <span className="flex min-w-0 items-center gap-3">
        <AuthorAvatar name={row.displayName} avatarUrl={row.avatarUrl} className="h-8 w-8" />
        {row.username ? (
          <Link
            href={`/u/${row.username}`}
            className="truncate text-base font-medium hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
          >
            {row.displayName}
          </Link>
        ) : (
          <span className="truncate text-base font-medium">{row.displayName}</span>
        )}
      </span>
      <span className="hidden text-right font-mono text-[13px] text-fg-muted sm:block">{row.scoredPicks}</span>
      <span className="text-right font-slab text-[22px] leading-none">{row.totalPoints.toLocaleString("en-US")}</span>
    </div>
  );
}

function YouRow({ standing, scope }: { standing: Standing; scope: LeaderboardScope }) {
  return (
    <div className={`${ROW_GRID} px-4 py-2.5`}>
      <span className="font-slab text-[24px] leading-none">{standing.rank}</span>
      <span className="min-w-0">
        <span className="block font-semibold">You</span>
        <span className="block type-label-xs text-panel-muted">{standingCopy(standing, scope).detail}</span>
      </span>
      <span className="hidden text-right font-mono text-[13px] text-panel-muted sm:block">{standing.scoredPicks}</span>
      <span className="text-right font-slab text-[22px] leading-none">{standing.totalPoints.toLocaleString("en-US")}</span>
    </div>
  );
}

/** Shown instead of a "you" row when the caller is not on the board, and why. */
function StandingNotice({ standing, scope }: { standing: Standing; scope: LeaderboardScope }) {
  const copy = standingCopy(standing, scope);
  return (
    <div className="rounded-card bg-surface-raised px-5 py-4 shadow-well">
      <p className="type-label font-semibold text-fg">{copy.headline}</p>
      <p className="mt-1.5 text-[15px] leading-6 text-fg-muted">{copy.detail}</p>
    </div>
  );
}
