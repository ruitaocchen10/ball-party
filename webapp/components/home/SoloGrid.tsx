import { ChevronDown, Gamepad2 } from "lucide-react";
import type { ReactNode } from "react";

import { GAMES, type Game, type SoloMode } from "@/lib/platform/orchestration/catalog";
import { playSolo } from "@/lib/platform/lobbies/actions";
import { SoloSeasonRange } from "./SoloSeasonRange";

/** The seasons on offer for Higher or Lower's era picker; absent when the bounds could not be read. */
export type SoloEra = { seasonMin: number; seasonMax: number };

/**
 * Higher or Lower's scoring choice, sent as `scoring_mode`. Kept here rather
 * than on the catalogue's `soloModes` because that field also tells the
 * sidebar to send a player to this page instead of starting in one tap, and
 * Higher or Lower's settings are optional — the one-tap entry stays.
 */
const HIGHER_OR_LOWER_SCORING: readonly SoloMode[] = [
  { value: "season_total", label: "Season total", description: "Whole-season PPR points." },
  { value: "weekly", label: "Weekly PPR", description: "A single game's PPR points." },
];

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
 * Only a game with `solo: true` and `status: "live"` shows up here. No
 * account-gated fallback the way GameGrid's tiles have one: solo carries none of hosting's account requirement, so a session
 * that can't play solo is a session with nothing here to act on at all, and
 * the card just drops its Play solo control rather than offering one it
 * can't use.
 */
export function SoloGrid({ canPlaySolo, higherOrLowerEra = null }: { canPlaySolo: boolean; higherOrLowerEra?: SoloEra | null }) {
  const games = GAMES.filter((game) => game.solo && game.status === "live");

  if (games.length === 0) return <NoSoloGames />;

  return (
    <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {games.map((game) => (
        <li key={game.slug} className="flex">
          <SoloCard game={game} canPlaySolo={canPlaySolo} higherOrLowerEra={higherOrLowerEra} />
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
function SoloCard({ game, canPlaySolo, higherOrLowerEra }: { game: Game; canPlaySolo: boolean; higherOrLowerEra: SoloEra | null }) {
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
          {game.soloModes || game.soloEras ? (
            <SoloSettings>
              {game.soloModes ? <RadioChoice name="mode" legend="Ratings" options={game.soloModes} /> : null}
              {game.soloEras ? <RadioChoice name="era" legend="Era" options={game.soloEras} /> : null}
            </SoloSettings>
          ) : null}
          {game.match === "higher_or_lower" ? (
            <SoloSettings>
              <RadioChoice name="scoring_mode" legend="Scoring" options={HIGHER_OR_LOWER_SCORING} />
              {higherOrLowerEra ? <SoloSeasonRange era={higherOrLowerEra} /> : null}
            </SoloSettings>
          ) : null}
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

/**
 * The card's start-time choices, tucked behind a disclosure so a card that has
 * some doesn't tower over one that has none. A native `<details>` rather than
 * client state: it needs no script, and the radios inside stay in the form
 * whether it is open or shut, so a collapsed card still starts a run with the
 * defaults (or whatever was picked before it was closed).
 */
function SoloSettings({ children }: { children: ReactNode }) {
  return (
    <details className="group/settings mb-3">
      <summary className="flex cursor-pointer list-none items-center justify-between font-mono text-[9px] font-semibold tracking-[0.1em] text-fg-muted uppercase transition-colors marker:hidden hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel [&::-webkit-details-marker]:hidden">
        Settings
        <ChevronDown
          aria-hidden
          className="h-3.5 w-3.5 transition-transform group-open/settings:rotate-180"
          strokeWidth={1.75}
        />
      </summary>
      <div className="mt-3">{children}</div>
    </details>
  );
}

/**
 * A choice the run is locked to once it starts, made on the card because
 * there is no screen before the run to make it on. Plain radios so the choice
 * travels with the form under `name` and the card still works with no client
 * script; the first option is the default and starts checked. Shared by
 * `soloModes` (`name="mode"`) and `soloEras` (`name="era"`) — two independent
 * choices of the same shape, so one renderer is both fieldsets.
 */
function RadioChoice({ name, legend, options }: { name: string; legend: string; options: readonly SoloMode[] }) {
  return (
    <fieldset className="mb-3 flex flex-col gap-1.5">
      <legend className="mb-1.5 font-mono text-[9px] font-semibold tracking-[0.1em] text-fg-muted uppercase">
        {legend}
      </legend>
      {options.map((option, index) => (
        <label
          key={option.value}
          className="flex cursor-pointer items-start gap-2 border border-line px-2.5 py-2 transition-colors has-checked:border-fg has-checked:bg-surface has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-panel"
        >
          <input
            type="radio"
            name={name}
            value={option.value}
            defaultChecked={index === 0}
            className="mt-0.5 accent-current"
          />
          <span className="flex flex-col">
            <span className="font-mono text-[11px] font-bold tracking-[0.1em] uppercase">{option.label}</span>
            <span className="text-[12px] leading-4 text-fg-muted">{option.description}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}

/** Solo's honest-empty state, for the day no solo game is live — say so
 *  plainly rather than showing nothing. */
function NoSoloGames() {
  return (
    <div className="rounded-card bg-surface-raised px-5 py-6 text-sm leading-6 text-fg-muted shadow-well">
      No game deals for one player right now. Check back soon.
    </div>
  );
}
