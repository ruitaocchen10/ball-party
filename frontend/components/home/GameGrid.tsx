import { Concealed } from "@/components/ui/Concealed";
import { GAMES, type Game } from "@/lib/games/catalog";

/**
 * The shop window. Three of four games need four people, so most cards do not
 * start a match — they start a room seeded with that game, and the real choice
 * still happens inside the room when someone starts a run. Only a game marked
 * `solo` gets a CTA that means "play, now, alone".
 */
export function GameGrid({ signedIn }: { signedIn: boolean }) {
  return (
    <ul className="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
      {GAMES.map((game) => (
        <li key={game.slug} className="flex">
          {game.status === "development" ? <InDevelopment /> : <GameCard game={game} signedIn={signedIn} />}
        </li>
      ))}
    </ul>
  );
}

function GameCard({ game, signedIn }: { game: Game; signedIn: boolean }) {
  const cta = !signedIn ? "Sign in" : game.solo ? "Play solo" : "Start a room";

  return (
    <article className="flex w-full flex-col overflow-hidden rounded-card bg-panel text-panel-fg shadow-card">
      <span aria-hidden className="block h-[5px] shrink-0 bg-hidden" />
      <div className="flex flex-1 flex-col p-3 sm:p-3.5">
        <p className="mb-1.5 font-mono text-[8px] tracking-[0.17em] text-hidden uppercase">
          {game.kind}
        </p>
        <h3 className="mb-2 font-slab text-base leading-[1.04] -skew-x-7 uppercase sm:text-xl">
          {game.name.map((line) => (
            <span key={line} className="block">
              {line}
            </span>
          ))}
        </h3>
        <p className="mb-3.5 hidden text-[12.5px] leading-[1.5] text-[#4c4739] lg:block">
          {game.tagline}
        </p>

        <div className="mt-auto flex flex-col items-start gap-2 border-t border-dashed border-[#c7bfac] pt-2.5 sm:flex-row sm:items-center sm:justify-between">
          <p className="font-mono text-[9px] leading-[1.5] tracking-[0.1em] text-panel-muted uppercase">
            {game.players}
            {game.duration ? (
              <>
                <br />
                {game.duration}
              </>
            ) : null}
          </p>
          {/* Not a button yet: no game is implemented, so this would be a
              control that lies. It becomes a <form> per game as each ships. */}
          <span className="rounded-[3px] border border-dashed border-[#c7bfac] px-2 py-1 font-mono text-[9px] font-bold tracking-[0.13em] text-panel-muted uppercase">
            {cta}
          </span>
        </div>
      </div>
    </article>
  );
}

/** A game nobody can play yet is concealed, not greyed out — red already means
 *  "not revealed" everywhere else in the product. */
function InDevelopment() {
  return (
    <Concealed
      label="Another game in development"
      className="flex w-full items-center justify-center p-6 text-center"
    >
      <div className="relative">
        <p className="font-slab text-base leading-[1.1] -skew-x-7 text-panel/95 uppercase sm:text-lg">
          In
          <br />
          development
        </p>
        <p className="mt-2.5 font-mono text-[9px] tracking-[0.15em] text-panel/80 uppercase">
          Coming soon
        </p>
      </div>
    </Concealed>
  );
}
