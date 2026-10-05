"use client";

import { AnimatePresence, motion } from "motion/react";
import { Flame, Trophy } from "lucide-react";

import { Card } from "@/components/foundation/ui-kit/Card";
import { Concealed } from "@/components/foundation/ui-kit/Concealed";
import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";
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
 */
export function MemberRoster({
  members,
  hostId,
  viewerId,
  stats,
  capacity,
}: {
  members: Member[];
  hostId: string;
  viewerId: string;
  stats: Record<string, ProfileSummary>;
  capacity: number;
}) {
  const emptySeats = Math.max(0, capacity - members.length);

  return (
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
            <Card edge={false} className="h-full min-h-64 border-t-[5px] border-hidden">
              <div className="flex h-full flex-col items-center px-3 py-4 text-center sm:py-5">
                <span className="self-start type-label text-panel-muted">
                  Seat {seat + 1}
                </span>
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
                <span className="mt-2 block min-h-3 type-label text-panel-muted">
                  {[
                    member.user_id === hostId ? "host" : null,
                    member.profiles?.is_guest ? "playing now" : null,
                    member.user_id === viewerId ? "you" : null,
                  ]
                    .filter(Boolean)
                    .join(" · ") || "at the table"}
                </span>
              </div>
            </Card>
          </motion.li>
        ))}
      </AnimatePresence>
      {Array.from({ length: emptySeats }, (_, index) => (
        <li key={`empty-${index}`}>
          <Concealed label="Open spot, waiting for a player" className="flex h-full min-h-64 items-center justify-center">
            <span className="relative px-3 text-center">
              <span className="block font-slab text-2xl leading-none uppercase">Open seat</span>
              <span className="mt-2 block type-label text-panel">Invite a friend</span>
            </span>
          </Concealed>
        </li>
      ))}
    </ul>
  );
}

const EMPTY_SUMMARY: ProfileSummary = { gamesPlayed: 0, wins: 0, winRate: 0, bestStreak: 0, recent: [] };

/** Incoming form belongs beside the player it describes, not in a second rail. */
function PlayerForm({ summary }: { summary: ProfileSummary }) {
  if (summary.gamesPlayed === 0) {
    return <span className="mt-2 block type-label text-panel-muted">New</span>;
  }

  const recent = summary.recent.map((match) => (match.placement === 1 ? "win" : "loss")).join(", ");
  return (
    <div className="mt-2 flex flex-col items-center gap-1.5">
      <div className="flex items-center justify-center gap-3 font-mono text-[11px] font-semibold tabular-nums">
        <span className="flex items-center gap-1" aria-label={`${summary.winRate}% win rate`}>
          <Trophy aria-hidden className="h-3.5 w-3.5 text-hidden-text" strokeWidth={1.8} />
          {summary.winRate}%
        </span>
        <span className="flex items-center gap-1" aria-label={`Best streak ${summary.bestStreak}`}>
          <Flame aria-hidden className="h-3.5 w-3.5 text-hidden-text" strokeWidth={1.8} />
          {summary.bestStreak}
        </span>
      </div>
      <div className="flex gap-1" aria-label={`Recent form: ${recent}`}>
        {summary.recent.map((match) => {
          const won = match.placement === 1;
          return <span key={match.id} aria-hidden className={`h-1.5 w-1.5 rounded-full ${won ? "bg-hidden-text" : "bg-panel-muted/45"}`} />;
        })}
      </div>
    </div>
  );
}
