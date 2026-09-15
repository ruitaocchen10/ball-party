import { Gamepad2 } from "lucide-react";

import { GAMES, type Game } from "@/lib/games/catalog";
import { playSolo } from "@/lib/lobbies/actions";

/**
 * The games a lone player can start right now — carved out of the shop
 * window (see GameGrid) rather than living as a tile's second control there.
 * "Start a room" and "play alone" are different promises, and folding them
 * into one tile made the lesser one read as a footnote on the other.
 *
 * Cards read as a small games shelf — icon, a "1 player" tag, name, pitch,
 * then Play solo — rather than GameGrid's shop-window bento tiles: solo
 * needs none of that bidding-war framing, just "here's what you can play by
 * yourself right now."
 *
 * Only a game with `solo: true` and `status: "live"` shows up here — Higher
 * or Lower alone today. No account-gated fallback the way GameGrid's tiles
 * have one: solo carries none of hosting's account requirement, so a session
 * that can't play solo is a session with nothing here to act on at all, and
 * the card just drops its Play solo control rather than offering one it
 * can't use.
 */
export function SoloGrid({ canPlaySolo }: { canPlaySolo: boolean }) {
  const games = GAMES.filter((game) => game.solo && game.status === "live");

  if (games.length === 0) return <NoSoloGames />;

  return (
    <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {games.map((game) => (
        <li key={game.slug} className="flex">
          <SoloCard game={game} canPlaySolo={canPlaySolo} />
        </li>
      ))}
    </ul>
  );
}

/**
 * The card itself isn't the control — same split GameGrid uses between a
 * tile and its button — but it still reacts to a hover anywhere on it
 * (`group` sits here, not just on the button) so the whole card reads as
 * live even though only the Play solo button at the bottom actually is.
 */
function SoloCard({ game, canPlaySolo }: { game: Game; canPlaySolo: boolean }) {
  return (
    <article className="group flex w-full flex-col border border-line bg-surface-raised p-4 transition-colors hover:border-fg-muted">
      <div className="flex items-start justify-between gap-2">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center bg-surface text-fg-muted ring-1 ring-line ring-inset transition-colors group-hover:text-fg">
          <Gamepad2 aria-hidden className="h-[18px] w-[18px]" strokeWidth={1.6} />
        </span>
        <span className="bg-surface px-2 py-1 font-mono text-[9px] font-semibold tracking-[0.1em] text-fg-muted uppercase ring-1 ring-line ring-inset">
          1 player
        </span>
      </div>

      <h3 className="mt-4 font-slab text-xl leading-[1.04] uppercase">
        {game.name.map((line) => (
          <span key={line} className="block">
            {line}
          </span>
        ))}
      </h3>
      <p className="mt-2 text-[13px] leading-5 text-fg-muted">{game.tagline}</p>

      {canPlaySolo ? (
        <form action={playSolo} className="mt-4 border-t border-line pt-3">
          <input type="hidden" name="game" value={game.match ?? ""} />
          <button
            type="submit"
            className="inline-flex h-9 w-full cursor-pointer items-center justify-center bg-panel px-3.5 font-mono text-[11px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
          >
            Play solo
          </button>
        </form>
      ) : null}
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
