import { StartHigherOrLower } from "@/components/lobby/StartHigherOrLower";
import { StartRun, type Era } from "@/components/lobby/StartRun";
import { StartSabotageDraft } from "@/components/lobby/StartSabotageDraft";
import { Card } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import { GAMES } from "@/lib/games/catalog";

const CAPACITY = 4;

type Member = {
  user_id: string;
  last_seen_at?: string;
  profiles: { display_name: string; is_guest?: boolean } | null;
};

/**
 * The room is a durable party table, rather than an antechamber for one game.
 * A catalogue card is therefore the contract a new game gets when it arrives:
 * what it is, how many people it needs, how long it lasts, and whether it can
 * be started today.
 */
export function LobbyLineup({
  lobbyId,
  code,
  members,
  hostId,
  viewerId,
  isHost,
  inFlight,
  hostIsActive = true,
  era = null,
  higherOrLowerEra = null,
}: {
  lobbyId: string;
  code: string;
  members: Member[];
  hostId: string;
  viewerId: string;
  isHost: boolean;
  inFlight: boolean;
  hostIsActive?: boolean;
  // Auction-specific, like the start control it is handed to. The catalogue
  // card is the seam where the room stops being general and starts being one
  // game; this rides along the same seam rather than opening a second one.
  era?: Era | null;
  higherOrLowerEra?: { seasonMin: number; seasonMax: number } | null;
}) {
  const emptySeats = Math.max(0, CAPACITY - members.length);

  return (
    <section aria-labelledby="lineup-heading" className="flex flex-col gap-5 lg:gap-6">
      <div>
        <p className="font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">
          Tonight&apos;s lineup
        </p>
        <h2
          id="lineup-heading"
          className="mt-1 font-slab text-2xl leading-none -skew-x-7 uppercase sm:text-3xl"
        >
          Tonight&apos;s lineup
        </h2>
        <p className="mt-2 text-sm leading-5 text-fg-muted">
          {isHost
            ? "Pick a game when the party is ready. More are on their way."
            : hostIsActive
              ? "The host starts when the party is ready. More games are on their way."
              : "The host is away. You can take host controls to keep the party moving."}
        </p>
      </div>

      <ul className="-mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2 sm:-mx-6 sm:px-6 md:mx-0 md:grid md:grid-cols-3 md:overflow-visible md:px-0 lg:gap-4 xl:gap-5">
        {GAMES.map((game) => {
          // A tile can be started when the catalogue says which durable match
          // record it deals. That is a stricter promise than `live`, which is
          // only what the home screen may advertise, and the two run in
          // opposite directions while a game is being built in slices — so the
          // kicker below says which of the two this card is.
          const launchable = game.match !== null;
          const meta = [game.players, game.duration].join(" · ");

          return (
            <li key={game.slug} className="w-[15.5rem] shrink-0 snap-start md:w-auto">
              {launchable ? (
                <Card className="flex h-full flex-col">
                  <div className="flex flex-1 flex-col p-3.5">
                    <p className="font-mono text-[10px] tracking-[0.13em] text-hidden-ink uppercase">
                      {game.status === "live" ? "Next up · live" : "Next up · in development"}
                    </p>
                    <h3 className="mt-2 font-slab text-xl leading-[1.04] -skew-x-7 uppercase">
                      {game.name.map((line) => (
                        <span key={line} className="block">
                          {line}
                        </span>
                      ))}
                    </h3>
                    <p className="mt-2 text-sm leading-5 text-[#4c4739]">{game.tagline}</p>
                    <p className="mt-auto border-t border-dashed border-[#c7bfac] pt-3 font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
                      {meta}
                    </p>
                  </div>
                  {isHost && !inFlight ? (
                    <div className="border-t border-[#c7bfac] bg-panel-shade p-2.5">
                      {game.match === "higher_or_lower" ? (
                        <StartHigherOrLower lobbyId={lobbyId} code={code} players={members.length} era={higherOrLowerEra} />
                      ) : game.match === "sabotage_draft" ? (
                        <StartSabotageDraft lobbyId={lobbyId} code={code} players={members.length} />
                      ) : (
                        <StartRun lobbyId={lobbyId} code={code} players={members.length} era={era} />
                      )}
                    </div>
                  ) : null}
                </Card>
              ) : (
                <article className="flex h-full flex-col rounded-card border border-line bg-surface-raised p-3.5">
                  <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Coming soon</p>
                  <h3 className="mt-2 font-slab text-xl leading-[1.04] -skew-x-7 text-fg uppercase">
                    {game.name.map((line) => (
                      <span key={line} className="block">
                        {line}
                      </span>
                    ))}
                  </h3>
                  <p className="mt-2 text-sm leading-5 text-fg-muted">{game.tagline}</p>
                  <p className="mt-auto border-t border-line pt-3 font-mono text-[10px] tracking-[0.11em] text-fg-muted uppercase">
                    {meta}
                  </p>
                </article>
              )}
            </li>
          );
        })}
      </ul>

      <div className="flex items-center justify-between gap-3">
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">At the table</p>
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          {members.length} of {CAPACITY} players
        </p>
      </div>

      <ul className="grid grid-cols-2 gap-2.5 md:grid-cols-4 lg:gap-4 xl:gap-5">
        {members.map((member) => (
          <li key={member.user_id}>
            <Card edge={false} className="h-full border-t-[5px] border-hidden">
              <div className="px-3 pt-2.5 pb-3">
                <span className="block font-slab text-lg leading-none -skew-x-7 uppercase">
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
          </li>
        ))}
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
    </section>
  );
}
