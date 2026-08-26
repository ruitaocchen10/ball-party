"use client";

import { AnimatePresence, motion } from "motion/react";

import { Card } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import { DURATION, EASE_OUT } from "@/lib/motion";

type Member = {
  user_id: string;
  last_seen_at?: string;
  profiles: { display_name: string; is_guest?: boolean } | null;
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
    <ul className="grid grid-cols-2 gap-2.5 md:grid-cols-4 lg:gap-4 xl:gap-5">
      <AnimatePresence>
        {members.map((member) => (
          <motion.li
            key={member.user_id}
            layout
            initial={{ opacity: 0, scale: 0.94 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.94 }}
            transition={{ duration: DURATION.base, ease: EASE_OUT }}
          >
            <Card edge={false} className="h-full border-t-[5px] border-hidden">
              <div className="px-3 pt-2.5 pb-3">
                <span className="block font-slab text-lg leading-none uppercase">
                  {member.profiles?.display_name ?? "Unknown player"}
                </span>
                <span className="mt-2 block font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
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
          <Concealed label="Open spot, waiting for a player" className="flex h-full min-h-[73px] items-center">
            <span className="relative w-full text-center font-mono text-[10px] tracking-[0.15em] text-panel uppercase">
              Invite friend
            </span>
          </Concealed>
        </li>
      ))}
    </ul>
  );
}
