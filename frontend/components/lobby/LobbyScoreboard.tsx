import { Trophy } from "lucide-react";

type Member = {
  user_id: string;
  profiles: { display_name: string; is_guest?: boolean } | null;
};

/**
 * Wins this room's members have picked up since it opened — see
 * lib/lobbies/scoreboard.ts for where the count comes from and why it resets
 * with the room instead of following anyone past it.
 *
 * Takes a plain win count per member rather than reaching for the database
 * itself: the page already has to read the roster, and a second component
 * doing its own fetch would just be two places deciding who's "in" this room.
 */
export function LobbyScoreboard({
  members,
  wins,
}: {
  members: Member[];
  wins: Record<string, number>;
}) {
  const ranked = [...members].sort((a, b) => (wins[b.user_id] ?? 0) - (wins[a.user_id] ?? 0));
  const anyWins = ranked.some((member) => (wins[member.user_id] ?? 0) > 0);

  return (
    <section aria-labelledby="scoreboard-heading" className="flex flex-col gap-3">
      <div>
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">This session</p>
        <h2 id="scoreboard-heading" className="mt-1 font-slab text-2xl leading-none uppercase">
          Scoreboard
        </h2>
      </div>

      {anyWins ? (
        <ol className="flex flex-col gap-1.5">
          {ranked.map((member) => {
            const count = wins[member.user_id] ?? 0;
            const leading = anyWins && count > 0 && count === (wins[ranked[0]!.user_id] ?? 0);
            return (
              <li
                key={member.user_id}
                className="flex items-center justify-between gap-2 rounded-card bg-surface-raised px-3 py-2 ring-1 ring-line ring-inset"
              >
                <span className="flex min-w-0 items-center gap-2">
                  {leading ? (
                    <Trophy aria-hidden className="h-3.5 w-3.5 shrink-0 text-panel" strokeWidth={1.5} />
                  ) : null}
                  <span className="truncate font-mono text-xs font-semibold tracking-[0.03em] text-fg uppercase">
                    {member.profiles?.display_name ?? "Player"}
                  </span>
                </span>
                <span className="shrink-0 font-mono text-xs font-bold text-fg tabular-nums">
                  {count} {count === 1 ? "win" : "wins"}
                </span>
              </li>
            );
          })}
        </ol>
      ) : (
        <p className="text-sm leading-5 text-fg-muted">No wins yet this session — first one takes the board.</p>
      )}
    </section>
  );
}
