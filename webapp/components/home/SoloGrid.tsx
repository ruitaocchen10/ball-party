import { Gamepad2 } from "lucide-react";

import { GAMES, type Game, type SoloMode } from "@/lib/platform/orchestration/catalog";
import { playSolo } from "@/lib/platform/lobbies/actions";
import { SoloPlayControls, type SoloChoice } from "./SoloPlayControls";
import { Badge } from "@/components/foundation/ui-kit/Badge";

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
 * The games a lone player can start right now. "Start a room" and "play
 * alone" are different promises, so solo has its own page rather than a
 * second control on a party tile.
 *
 * Cards read as a small games shelf — icon, a "1 player" tag, name, pitch,
 * then Play beside a settings button that opens the start-time choices in a
 * dialog: just "here's what you can play by yourself right now."
 *
 * Only a game with `solo: true` and `status: "live"` shows up here. No
 * account-gated fallback: solo carries none of hosting's account requirement. A visitor with no session at all plays as
 * a guest — `playSolo` creates the session — so every card carries its Play
 * control.
 */
export function SoloGrid({ higherOrLowerEra = null }: { higherOrLowerEra?: SoloEra | null }) {
  const games = GAMES.filter((game) => game.solo && game.status === "live");

  if (games.length === 0) return <NoSoloGames />;

  return (
    <ul className="grid grid-cols-2 gap-3">
      {games.map((game) => (
        <li key={game.slug} className="flex">
          <SoloCard game={game} higherOrLowerEra={higherOrLowerEra} />
        </li>
      ))}
    </ul>
  );
}

/**
 * The card itself isn't the control, but it still reacts to a hover anywhere on it
 * (`group` sits here, not just on the button) so the whole card reads as
 * live even though only the Play button at the bottom actually is.
 */
function SoloCard({ game, higherOrLowerEra }: { game: Game; higherOrLowerEra: SoloEra | null }) {
  const choices: SoloChoice[] = [];
  if (game.soloModes) choices.push({ name: "mode", legend: "Grades", options: game.soloModes });
  if (game.soloEras) choices.push({ name: "era", legend: "Era", options: game.soloEras });
  if (game.match === "higher_or_lower") {
    choices.push({ name: "scoring_mode", legend: "Scoring", options: HIGHER_OR_LOWER_SCORING });
  }
  const title = game.name.join(" ");

  return (
    <article className="group flex w-full flex-col rounded-card border border-line bg-surface-raised p-3 sm:p-4 transition-colors hover:border-fg-muted">
      <div className="flex items-start justify-between gap-2">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-chip bg-surface text-fg-muted ring-1 ring-line ring-inset transition-colors group-hover:text-fg">
          <Gamepad2 aria-hidden className="h-[18px] w-[18px]" strokeWidth={1.6} />
        </span>
        <Badge tone="muted" size="xs">1 player</Badge>
      </div>

      <h3 className="mt-4 font-slab text-xl leading-[1.04] uppercase">
        {game.name.map((line) => (
          <span key={line} className="block">
            {line}
          </span>
        ))}
      </h3>
      <p className="mt-2 mb-4 text-[13px] leading-5 text-fg-muted">{game.tagline}</p>

      <form action={playSolo} className="mt-auto border-t border-line pt-3">
        <input type="hidden" name="game" value={game.match ?? ""} />
        <SoloPlayControls
          title={title}
          choices={choices}
          era={game.match === "higher_or_lower" ? higherOrLowerEra : null}
        />
      </form>
    </article>
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
