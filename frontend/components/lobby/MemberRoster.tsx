"use client";

import { AnimatePresence, motion } from "motion/react";

import { Card } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import { ProfileAvatar } from "@/components/profile/ProfileAvatar";
import { DURATION, EASE_OUT } from "@/lib/motion";

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
  hostIsActive,
  capacity,
}: {
  members: Member[];
  hostId: string;
  viewerId: string;
  hostIsActive: boolean;
  capacity: number;
}) {
  const emptySeats = Math.max(0, capacity - members.length);

  return (
    <ul aria-label="Players at the table" className="grid grid-cols-2 gap-2.5 md:grid-cols-4 lg:gap-4 xl:gap-5">
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
            <Card edge={false} className="h-full min-h-52 border-t-[5px] border-hidden">
              <div className="flex h-full flex-col items-center px-3 py-4 text-center sm:py-5">
                <span className="self-start font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
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
                <span className="mt-2 block min-h-3 font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
                  {[
                    member.user_id === hostId ? "host" : null,
                    member.user_id === hostId && !hostIsActive ? "away" : null,
                    member.profiles?.is_guest ? "guest" : null,
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
          <Concealed label="Open spot, waiting for a player" className="flex min-h-52 items-center justify-center">
            <span className="relative px-3 text-center">
              <span className="block font-slab text-2xl leading-none uppercase">Open seat</span>
              <span className="mt-2 block font-mono text-[10px] tracking-[0.15em] text-panel uppercase">Invite a friend</span>
            </span>
          </Concealed>
        </li>
      ))}
    </ul>
  );
}
