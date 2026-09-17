import { ButtonLink } from "@/components/foundation/ui-kit/Button";

const CAPACITY = 4;

export type RoomSummary = {
  code: string;
  /** Current occupants, host first is not assumed — order is arrival order. */
  players: { id: string; name: string }[];
  hostId: string;
  youId: string;
};

/**
 * The room you are already in, on the home screen.
 *
 * This exists because a player is in exactly one lobby at a time (see
 * private.leave_all_lobbies in migration 0005) and nothing outside the room
 * page used to say so. Close the tab mid-lobby and the only way back was
 * remembering five characters.
 *
 * A cream panel, because this is now the most important object on the page and
 * that is what cream means here. Its buttons invert for the same reason.
 */
export function CurrentRoom({
  room,
  compact = false,
  headingId = "room-heading",
}: {
  room: RoomSummary;
  /** The party page uses the same room summary in its narrow desktop rail. */
  compact?: boolean;
  /** Lets responsive copies avoid duplicate heading ids in the document. */
  headingId?: string;
}) {
  const openSeats = Math.max(0, CAPACITY - room.players.length);

  return (
    <section aria-labelledby={headingId} className={compact ? "" : "pt-7"}>
      <h2 id={headingId} className="sr-only">
        Your room
      </h2>

      <div className="relative overflow-hidden rounded-card bg-panel text-panel-fg shadow-card">
        <span aria-hidden className="block h-[5px] bg-hidden" />

        <div className={`flex flex-col p-4 ${compact ? "gap-4" : "gap-5 sm:p-5 lg:flex-row lg:items-center lg:gap-8"}`}>
          <div className="shrink-0">
            <p className="mb-1.5 font-mono text-[10px] tracking-[0.16em] text-hidden-ink uppercase">
              You&apos;re in a room
            </p>
            <p className="font-mono text-[34px] leading-none font-semibold tracking-[0.16em] sm:text-[40px]">
              {room.code}
            </p>
          </div>

          <div className="min-w-0 flex-1">
            <p className="mb-2 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
              {room.players.length} of {CAPACITY} players
            </p>
            <ul className="flex flex-wrap items-center gap-1.5">
              {room.players.map((player) => (
                <li
                  key={player.id}
                  className="bg-panel-shade px-2 py-1 font-mono text-[10px] tracking-[0.1em] uppercase"
                >
                  {player.name}
                  {player.id === room.hostId || player.id === room.youId ? (
                    <span className="text-panel-muted">
                      {" · "}
                      {player.id === room.youId ? "you" : "host"}
                    </span>
                  ) : null}
                </li>
              ))}

              {/* Same rule as inside the room: a spot nobody has filled is red. */}
              {Array.from({ length: openSeats }, (_, i) => (
                <li
                  key={`open-${i}`}
                  className="bg-hidden px-2 py-1 font-mono text-[10px] tracking-[0.1em] text-panel/90 uppercase"
                >
                  Open spot
                </li>
              ))}
            </ul>
          </div>

          <ButtonLink
            href={`/lobby/${room.code}`}
            variant="ink"
            fullWidth={compact}
            className={compact ? "px-7" : "w-full px-7 lg:w-auto"}
          >
            Back to room
          </ButtonLink>
        </div>
      </div>
    </section>
  );
}
