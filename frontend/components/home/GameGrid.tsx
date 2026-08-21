import Link from "next/link";

import { Concealed } from "@/components/ui/Concealed";
import { GAMES, type Game } from "@/lib/games/catalog";
import { createLobby, playSolo } from "@/lib/lobbies/actions";
import { HOST_SIGN_UP_HREF } from "@/lib/lobbies/hosting";

/**
 * The shop window, and the primary way into the product: every tile is a
 * control that opens a room with that game in mind. Three of four games need
 * four people, so a tile does not start a match — the real choice still
 * happens inside the room when someone starts a run.
 *
 * Guests and signed-out visitors see a sign-up link instead of a form. Creating
 * a room needs an account, and a button that fails is worse than a link that explains.
 *
 * `canPlaySolo` gates a second, independent control on any tile whose game can
 * deal for one player — true for any session, guest included, since playing
 * solo carries none of hosting's account requirement. A signed-out visitor
 * sees neither: there is nothing here yet for `createLobby` or `playSolo` to
 * act on behalf of.
 *
 * Layout is a bento rather than four equal tiles: one game carries the product
 * and the grid should say so. The featured tile is placed explicitly at the
 * top-left 2×2, which reserves those cells so the remaining tiles auto-flow
 * down the last column regardless of catalog order.
 */
export function GameGrid({
  canCreateLobby,
  canPlaySolo,
}: {
  canCreateLobby: boolean;
  canPlaySolo: boolean;
}) {
  const live = GAMES.filter((game) => game.status === "live");
  const upcoming = GAMES.filter((game) => game.status === "development");

  return (
    <ul className="grid grid-cols-2 gap-3 lg:grid-cols-3 lg:gap-4 xl:gap-5">
      {live.map((game) => (
        <li
          key={game.slug}
          className={
            game.featured
              ? "col-span-2 flex lg:col-span-2 lg:col-start-1 lg:row-span-2 lg:row-start-1"
              : "col-span-1 flex"
          }
        >
          <GameCard
            game={game}
            canCreateLobby={canCreateLobby}
            canPlaySolo={canPlaySolo}
            featured={game.featured}
          />
        </li>
      ))}

      {upcoming.length > 0 ? (
        <li className="col-span-2 lg:col-span-3">
          <InDevelopment count={upcoming.length} />
        </li>
      ) : null}
    </ul>
  );
}

function GameCard({
  game,
  canCreateLobby,
  canPlaySolo,
  featured,
}: {
  game: Game;
  canCreateLobby: boolean;
  canPlaySolo: boolean;
  featured: boolean;
}) {
  const meta = [game.players, game.duration].filter(Boolean).join(" · ");

  return (
    <article
      className={
        "relative flex w-full flex-col overflow-hidden rounded-card bg-panel text-panel-fg " +
        "shadow-card transition-[transform,box-shadow] duration-150 ease-out " +
        "hover:-translate-y-0.5 hover:shadow-card-hover " +
        "focus-within:-translate-y-0.5 focus-within:shadow-card-hover active:translate-y-0"
      }
    >
      <span aria-hidden className="block h-[5px] shrink-0 bg-hidden" />

      <div className={`flex flex-1 flex-col ${featured ? "p-4 sm:p-5" : "p-3.5"}`}>
        {/* The featured tile is two rows tall, so its content is centred in
            what that buys rather than parked at the top over a hole. */}
        <div className={featured ? "flex flex-1 flex-col justify-center" : "contents"}>
          <p className="mb-2 font-mono text-[10px] tracking-[0.16em] text-hidden-ink uppercase">
            {game.kind}
          </p>

          <h3
            className={`mb-2.5 font-slab leading-[1.04] -skew-x-7 uppercase ${
              featured ? "text-2xl sm:text-4xl" : "text-base sm:text-xl"
            }`}
          >
            {game.name.map((line) => (
              <span key={line} className="block">
                {line}
              </span>
            ))}
          </h3>

          {/* The featured tile has the room to say what the game is at every
              size; the small ones only earn it once the column is wide. */}
          <p
            className={`text-[#4c4739] ${
              featured
                ? "max-w-[46ch] text-sm leading-[1.55] sm:text-[15px]"
                : "mb-3.5 hidden text-[12.5px] leading-[1.5] lg:block"
            }`}
          >
            {game.tagline}
          </p>

          {featured ? <Lots /> : null}
        </div>

        {/* The tiles in the narrow column stack: at ~290px of usable width a
            row puts "start a room" on two lines. Full-width there turns the
            wrap into a bar you can hit instead. */}
        <div
          className={`mt-auto border-t border-dashed border-[#c7bfac] ${
            featured
              ? "flex flex-col items-start gap-2.5 pt-4 sm:flex-row sm:items-center sm:justify-between"
              : "flex flex-col items-stretch gap-2.5 pt-3"
          }`}
        >
          <p className="font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
            {meta}
          </p>
          <Action
            game={game}
            canCreateLobby={canCreateLobby}
            canPlaySolo={canPlaySolo}
            stretch={!featured}
          />
        </div>
      </div>
    </article>
  );
}

/**
 * The tile's one control. It stretches to cover the whole card — the card
 * looks pressable, so all of it should be — while staying a single real
 * button, so the tile is one tab stop and the accessible name is the verb.
 */
const ACTION =
  "inline-flex h-9 cursor-pointer items-center rounded-[3px] bg-panel-fg px-3.5 " +
  "font-slab text-[13px] tracking-[0.04em] -skew-x-7 text-panel uppercase " +
  "transition-colors hover:bg-[#2c2921] " +
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg";

/**
 * The rest of the tile, made to do what the tile looks like it does.
 *
 * A second control rather than a pseudo-element stretched off the first: the
 * visible one is skewed, and a transform makes an element the containing block
 * for its own absolute children, so `inset-0` there sizes to the button. This
 * sits in the form instead, where the nearest positioned ancestor is the card.
 *
 * Hidden from assistive tech and off the tab order on purpose — it is the same
 * action as the button beside it, and the tile should be one stop, not two.
 */
const OVERLAY = "absolute inset-0 cursor-pointer";

/**
 * The ghost counterpart to ACTION, for a tile's second control. Only a tile
 * offering solo play ever has two, so this exists solely to read as secondary
 * beside it — same skew, same face, a ring instead of a fill.
 */
const SOLO_ACTION =
  "inline-flex h-9 cursor-pointer items-center rounded-[3px] px-3.5 " +
  "font-slab text-[13px] tracking-[0.04em] -skew-x-7 text-panel-fg uppercase " +
  "ring-1 ring-inset ring-panel-fg/35 transition-colors hover:bg-panel-fg/10 " +
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg";

function Action({
  game,
  canCreateLobby,
  canPlaySolo,
  stretch,
}: {
  game: Game;
  canCreateLobby: boolean;
  canPlaySolo: boolean;
  stretch: boolean;
}) {
  const width = stretch ? "w-full justify-center" : "";
  const offerSolo = canPlaySolo && game.solo && game.match !== null;

  // The whole-card overlay only makes sense with one control: it is what to
  // click for the entire card's area, and a second real button beside it would
  // have its clicks stolen by an overlay sized to cover the whole tile. A tile
  // offering solo skips it and renders two ordinary buttons instead — same
  // host control either way, via HostControl below.
  if (!offerSolo) {
    if (!canCreateLobby) {
      return (
        <>
          <Link href={HOST_SIGN_UP_HREF} aria-hidden tabIndex={-1} className={OVERLAY} />
          <HostControl canCreateLobby={false} width={width} />
        </>
      );
    }

    return (
      <form action={createLobby} className={stretch ? "contents" : ""}>
        <button type="submit" aria-hidden tabIndex={-1} className={OVERLAY} />
        <HostControl canCreateLobby width={width} />
      </form>
    );
  }

  return (
    <div className={`flex gap-2 ${stretch ? "flex-col" : "flex-row"}`}>
      {canCreateLobby ? (
        <form action={createLobby} className={stretch ? "contents" : ""}>
          <HostControl canCreateLobby width={width} />
        </form>
      ) : (
        <HostControl canCreateLobby={false} width={width} />
      )}
      <form action={playSolo} className={stretch ? "contents" : ""}>
        <input type="hidden" name="game" value={game.match ?? ""} />
        <button type="submit" className={`${SOLO_ACTION} ${width}`}>
          Play solo
        </button>
      </form>
    </div>
  );
}

/**
 * The host-gated visible control: "Start a room" once signed in as an account
 * holder, "Create an account to host" otherwise. Split out because that
 * decision was written out twice — once for the tile's only control, once
 * for its shared-with-solo half. The submit button still needs a `<form>`
 * around it; that stays with each caller, since only one of them also owns
 * the click-anywhere overlay.
 */
function HostControl({ canCreateLobby, width }: { canCreateLobby: boolean; width: string }) {
  if (!canCreateLobby) {
    return (
      <Link href={HOST_SIGN_UP_HREF} className={`${ACTION} ${width}`}>
        Create an account to host
      </Link>
    );
  }

  return (
    <button type="submit" className={`${ACTION} ${width}`}>
      Start a room
    </button>
  );
}

/**
 * Four face-down lots, for the featured tile. Decoration, but not arbitrary:
 * the game is bidding on player-weeks whose fantasy points you cannot see, and
 * this is that — the same weave the product uses for concealed information
 * everywhere else. It also gives the double-height tile something to do with
 * the space its size buys.
 */
function Lots() {
  const tilt = ["-rotate-3", "rotate-1", "-rotate-1", "rotate-3"];

  return (
    <div aria-hidden className="mt-7 hidden gap-2.5 sm:flex">
      {tilt.map((rotation, i) => (
        <span
          key={i}
          className={`pattern-concealed h-[74px] w-[54px] rounded-[4px] bg-hidden shadow-[0_6px_14px_rgb(0_0_0/0.28)] ${rotation}`}
        />
      ))}
    </div>
  );
}

/** A game nobody can play yet is concealed, not greyed out — red already means
 *  "not revealed" everywhere else in the product. A strip rather than a tile:
 *  it is an announcement, and it was taking a quarter of the shop window to
 *  advertise nothing. */
function InDevelopment({ count }: { count: number }) {
  return (
    <Concealed
      label={`${count} more game in development`}
      className="flex flex-col items-start gap-1.5 px-4 py-2.5 sm:flex-row sm:items-center sm:justify-between sm:gap-4 sm:px-5"
    >
      <p className="relative font-slab text-[13px] leading-none -skew-x-7 text-panel uppercase">
        {count === 1 ? "One more game" : `${count} more games`} in development
      </p>
      <p className="relative font-mono text-[9px] tracking-[0.15em] text-panel uppercase">
        Coming soon
      </p>
    </Concealed>
  );
}
