import { MemberRoster } from "@/components/platform/lobbies/MemberRoster";
import type { ProfileSummary } from "@/lib/foundation/identity/summary";

const CAPACITY = 4;

type Member = {
  user_id: string;
  last_seen_at?: string;
  profiles: { display_name: string; avatar_url?: string | null; is_guest?: boolean } | null;
};

/**
 * The seat grid: who is actually in the room right now. What the room plays
 * next lives beside this rather than inside it — see `GameSelector` — so the
 * room's people, not its game catalogue, are what this screen leads with.
 */
export function LobbyLineup({
  members,
  hostId,
  viewerId,
  stats = {},
  lobbyId,
}: {
  members: Member[];
  hostId: string;
  viewerId: string;
  stats?: Record<string, ProfileSummary>;
  /** Lets an open seat invite a friend. */
  lobbyId?: string;
}) {
  return (
    <section aria-labelledby="lineup-heading" className="flex flex-col gap-5 lg:gap-6">
      <div className="flex items-end justify-between gap-3">
        <div>
          <p className="type-label text-hidden-text">At the table</p>
          <h2 id="lineup-heading" className="mt-1 font-slab text-3xl leading-none uppercase sm:text-4xl">
            Your party
          </h2>
        </div>
        <p className="pb-0.5 text-right type-label text-fg-muted">
          {members.length} of {CAPACITY} seats
        </p>
      </div>

      <MemberRoster
        members={members}
        hostId={hostId}
        viewerId={viewerId}
        stats={stats}
        capacity={CAPACITY}
        lobbyId={lobbyId}
      />
    </section>
  );
}
