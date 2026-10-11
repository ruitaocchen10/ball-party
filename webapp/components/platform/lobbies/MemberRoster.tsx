"use client";

import { AnimatePresence, motion } from "motion/react";
import { Flame, Plus, Trophy } from "lucide-react";
import { useState } from "react";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Card } from "@/components/foundation/ui-kit/Card";
import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";
import { InviteFriendsModal } from "@/components/platform/lobbies/InviteFriendsModal";
import { DURATION, EASE_OUT } from "@/lib/foundation/ui-kit/motion";
import type { ProfileSummary } from "@/lib/foundation/identity/summary";

type Member = {
  user_id: string;
  last_seen_at?: string;
  profiles: { display_name: string; avatar_url?: string | null; is_guest?: boolean } | null;
};

/**
 * "At the table"'s seat grid, split out of LobbyLineup.tsx (a server
 * component — see its own docstring) so the one genuinely live-updating list
 * in the lobby — players joining and leaving in real time, via
 * LobbyRealtime's `router.refresh()` — gets to animate. Members are keyed by
 * their stable `user_id`, so `AnimatePresence` + `layout` can tell a seat
 * that's still occupied from one that just changed hands.
 *
 * Empty-seat placeholders stay index-keyed and outside `AnimatePresence`:
 * there's no player identity to preserve across them, only a count.
 *
 * A taken seat is a light card and an open one is a dark dashed outline with a
 * red plus, so the people at the table stand out and the only loud thing left
 * in the grid is the way to fill it: an open seat opens the invite dialog.
 */
export function MemberRoster({
  members,
  hostId,
  viewerId,
  stats,
  capacity,
  lobbyId,
}: {
  members: Member[];
  hostId: string;
  viewerId: string;
  stats: Record<string, ProfileSummary>;
  capacity: number;
  /** Needed to invite from an open seat; without it the seat is just a marker. */
  lobbyId?: string;
}) {
  const emptySeats = Math.max(0, capacity - members.length);
  const [inviting, setInviting] = useState(false);

  return (
    <>
      <ul aria-label="Players at the table" className="grid grid-cols-2 gap-2.5 lg:gap-4 xl:gap-5">
        <AnimatePresence>
          {members.map((member, seat) => (
            <motion.li
              key={member.user_id}
              layout
              initial={{ opacity: 0, scale: 0.94 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.94 }}
              transition={{ duration: DURATION.base, ease: EASE_OUT }}
            >
              <Card tone="light" className="h-full min-h-64">
                <div className="flex h-full flex-col items-center px-3 py-4 text-center sm:py-5">
                  <div className="flex w-full items-center justify-between">
                    <span className="type-label text-surface/60">Seat {seat + 1}</span>
                    {member.user_id === hostId ? (
                      <Badge tone="ink" size="xs">
                        Host
                      </Badge>
                    ) : null}
                  </div>
                  <div className="my-auto py-3">
                    <ProfileAvatar
                      name={member.profiles?.display_name ?? "Unknown player"}
                      avatarUrl={member.profiles?.avatar_url ?? null}
                    />
                  </div>
                  <span className="block font-slab text-2xl leading-none uppercase">
                    {member.profiles?.display_name ?? "Unknown player"}
                  </span>
                  <PlayerForm summary={stats[member.user_id] ?? EMPTY_SUMMARY} />
                  <span className="mt-2 block min-h-3 type-label text-surface/60">
                    {member.profiles?.is_guest
                      ? "playing now"
                      : member.user_id === viewerId
                        ? "you"
                        : "at the table"}
                  </span>
                </div>
              </Card>
            </motion.li>
          ))}
        </AnimatePresence>
        {Array.from({ length: emptySeats }, (_, index) => (
          <li key={`empty-${index}`}>
            <OpenSeat onInvite={lobbyId ? () => setInviting(true) : undefined} />
          </li>
        ))}
      </ul>
      {inviting && lobbyId ? (
        <InviteFriendsModal lobbyId={lobbyId} onClose={() => setInviting(false)} />
      ) : null}
    </>
  );
}

/** An empty seat: a dashed outline and one red plus. A button when it can invite. */
function OpenSeat({ onInvite }: { onInvite?: () => void }) {
  const className =
    "flex h-full min-h-64 w-full flex-col items-center justify-center gap-3 rounded-card border-2 border-dashed border-fg/25 px-3 text-center";
  const body = (
    <>
      <span aria-hidden className="grid h-12 w-12 place-items-center rounded-full bg-hidden text-fg">
        <Plus className="h-6 w-6" strokeWidth={2.2} />
      </span>
      <span className="block font-slab text-2xl leading-none text-fg-muted uppercase">Open seat</span>
      <span className="block type-label text-hidden-text">Invite a friend</span>
    </>
  );

  return onInvite ? (
    <button
      type="button"
      onClick={onInvite}
      aria-label="Open seat. Invite a friend"
      className={`${className} transition-colors hover:border-fg/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg`}
    >
      {body}
    </button>
  ) : (
    <div className={className}>{body}</div>
  );
}

const EMPTY_SUMMARY: ProfileSummary = { gamesPlayed: 0, wins: 0, winRate: 0, bestStreak: 0, recent: [] };

/** Incoming form belongs beside the player it describes, not in a second rail. */
function PlayerForm({ summary }: { summary: ProfileSummary }) {
  if (summary.gamesPlayed === 0) {
    return <span className="mt-2 block type-label text-surface/60">New</span>;
  }

  const recent = summary.recent.map((match) => (match.placement === 1 ? "win" : "loss")).join(", ");
  return (
    <div className="mt-2 flex flex-col items-center gap-1.5">
      <div className="flex items-center justify-center gap-3 font-mono text-[11px] font-semibold tabular-nums">
        <span className="flex items-center gap-1" aria-label={`${summary.winRate}% win rate`}>
          <Trophy aria-hidden className="h-3.5 w-3.5 text-hidden-ink" strokeWidth={1.8} />
          {summary.winRate}%
        </span>
        <span className="flex items-center gap-1" aria-label={`Best streak ${summary.bestStreak}`}>
          <Flame aria-hidden className="h-3.5 w-3.5 text-hidden-ink" strokeWidth={1.8} />
          {summary.bestStreak}
        </span>
      </div>
      <div className="flex gap-1" aria-label={`Recent form: ${recent}`}>
        {summary.recent.map((match) => {
          const won = match.placement === 1;
          return <span key={match.id} aria-hidden className={`h-1.5 w-1.5 rounded-full ${won ? "bg-hidden-ink" : "bg-surface/30"}`} />;
        })}
      </div>
    </div>
  );
}
