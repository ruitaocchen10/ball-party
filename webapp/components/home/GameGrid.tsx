import Link from "next/link";

import { groupGames, type Game } from "@/lib/platform/orchestration/catalog";
import { createLobby } from "@/lib/platform/lobbies/actions";
import { HOST_SIGN_UP_HREF } from "@/lib/platform/lobbies/hosting";

/**
 * The shop window, and the primary way into the product: every tile is a
 * control that opens a room with that game in mind. Three of four games need
 * four people, so a tile does not start a match — the real choice still
 * happens inside the room when someone starts a run.
 *
 * Guests and signed-out visitors see a sign-up link instead of a form. Creating
 * a room needs an account, and a button that fails is worse than a link that explains.
 *
 * Solo play used to live here too, as a tile's second control. It moved to its
 * own section (see components/home/SoloGrid.tsx) — "start a room" and "play
 * alone" are different promises, and folding them into one tile made the
 * lesser one read as a footnote on the other rather than a real destination.
 *
 * Layout is a bento rather than four equal tiles: one game carries the product
 * and the grid should say so. The featured tile is placed explicitly at the
 * top-left 2×2, which reserves those cells so the remaining tiles auto-flow
 * down the last column regardless of catalog order.
 */
export function GameGrid({ canCreateLobby }: { canCreateLobby: boolean }) {
  const live = groupGames().filter((game) => game.status === "live");

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
          <GameCard game={game} canCreateLobby={canCreateLobby} featured={game.featured} />
        </li>
      ))}
    </ul>
  );
}

function GameCard({
  game,
  canCreateLobby,
  featured,
}: {
  game: Game;
  canCreateLobby: boolean;
  featured: boolean;
}) {
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
            className={`mb-2.5 font-slab leading-[1.04] uppercase ${
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
            {game.players}
          </p>
          <Action canCreateLobby={canCreateLobby} stretch={!featured} />
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
  "inline-flex h-9 cursor-pointer items-center bg-panel-fg px-3.5 " +
  "font-slab text-[13px] tracking-[0.04em] text-panel uppercase " +
  "transition-colors hover:bg-[#2c2921] " +
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg";

/**
 * The rest of the tile, made to do what the tile looks like it does.
 *
 * A second control rather than a pseudo-element stretched off the first: a
 * pseudo-element can't be a real `<a>` or `<button>`, so it can't carry the
 * href or form submission that makes the whole card clickable. This sits in
 * the form instead, where the nearest positioned ancestor is the card, so
 * `inset-0` covers the full tile.
 *
 * Hidden from assistive tech and off the tab order on purpose — it is the same
 * action as the button beside it, and the tile should be one stop, not two.
 */
const OVERLAY = "absolute inset-0 cursor-pointer";

function Action({ canCreateLobby, stretch }: { canCreateLobby: boolean; stretch: boolean }) {
  const width = stretch ? "w-full justify-center" : "";

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

/**
 * The host-gated visible control: "Start a room" once signed in as an account
 * holder, "Create an account to host" otherwise. Split out from `Action` so
 * that decision has one home rather than being copied at each call site. The
 * submit button still needs a `<form>` around it; that stays with the caller,
 * since only the hosting path also owns the click-anywhere overlay.
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
          className={`pattern-concealed h-[74px] w-[54px] bg-hidden shadow-[0_6px_14px_rgb(0_0_0/0.28)] ${rotation}`}
        />
      ))}
    </div>
  );
}
