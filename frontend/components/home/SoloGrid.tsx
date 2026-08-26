import { GAMES, type Game } from "@/lib/games/catalog";
import { playSolo } from "@/lib/lobbies/actions";

/**
 * The games a lone player can start right now — carved out of the shop
 * window (see GameGrid) rather than living as a tile's second control there.
 * "Start a room" and "play alone" are different promises, and folding them
 * into one tile made the lesser one read as a footnote on the other.
 *
 * Only a game with `solo: true` and `status: "live"` shows up here — Higher
 * or Lower alone today. No account-gated fallback the way GameGrid's tiles
 * have one: solo carries none of hosting's account requirement, so a session
 * that can't play solo is a session with nothing here to act on at all, and
 * this renders nothing for it rather than a control it can't use.
 */
export function SoloGrid({ canPlaySolo }: { canPlaySolo: boolean }) {
  const games = GAMES.filter((game) => game.solo && game.status === "live");

  if (games.length === 0) return <NoSoloGames />;

  return (
    <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      {games.map((game) => (
        <li key={game.slug} className="flex">
          <SoloCard game={game} canPlaySolo={canPlaySolo} />
        </li>
      ))}
    </ul>
  );
}

function SoloCard({ game, canPlaySolo }: { game: Game; canPlaySolo: boolean }) {
  return (
    <article className="flex w-full flex-col bg-panel text-panel-fg shadow-card">
      <span aria-hidden className="block h-[5px] shrink-0 bg-hidden" />

      <div className="flex flex-1 flex-col p-3.5">
        <p className="mb-2 font-mono text-[10px] tracking-[0.16em] text-hidden-ink uppercase">
          {game.kind}
        </p>

        <h3 className="mb-2.5 font-slab text-base leading-[1.04] uppercase sm:text-xl">
          {game.name.map((line) => (
            <span key={line} className="block">
              {line}
            </span>
          ))}
        </h3>

        <div className="mt-auto flex flex-col items-stretch gap-2.5 border-t border-dashed border-[#c7bfac] pt-3">
          <p className="font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
            {game.players}
          </p>

          {canPlaySolo ? (
            <form action={playSolo}>
              <input type="hidden" name="game" value={game.match ?? ""} />
              <button
                type="submit"
                className="inline-flex h-9 w-full cursor-pointer items-center justify-center bg-panel-fg px-3.5 font-slab text-[13px] tracking-[0.04em] text-panel uppercase transition-colors hover:bg-[#2c2921] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg"
              >
                Play solo
              </button>
            </form>
          ) : null}
        </div>
      </div>
    </article>
  );
}

/** Solo's honest-empty state, for the day the catalog's one solo game isn't
 *  live — say so plainly rather than showing nothing. */
function NoSoloGames() {
  return (
    <div className="rounded-card bg-surface-raised px-5 py-6 text-sm leading-6 text-fg-muted shadow-well">
      No game deals for one player right now. Check back soon.
    </div>
  );
}
