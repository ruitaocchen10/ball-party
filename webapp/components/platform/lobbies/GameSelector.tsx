"use client";

import { useState, type ReactNode } from "react";

import { StartHigherOrLower } from "@/components/platform/lobbies/StartHigherOrLower";
import { StartRun, type Era } from "@/components/platform/lobbies/StartRun";
import { StartSabotageDraft } from "@/components/platform/lobbies/StartSabotageDraft";
import { StartWavelength } from "@/components/platform/lobbies/StartWavelength";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { groupGames, type MatchGame } from "@/lib/platform/orchestration/catalog";
import { selectGame } from "@/lib/platform/lobbies/actions";

const LAUNCHABLE = groupGames().filter((game) => game.match !== null);

/**
 * The room's one "what's next" slot, always on screen rather than a grid of
 * every game competing for the same space. Picking and starting are two
 * separate steps on purpose — see `selectGame` in lib/lobbies/actions.ts — so
 * this renders whichever half of that is live: a picker when nothing (or a
 * change) is being chosen, the chosen game's own start card otherwise. The
 * selection itself survives a finished match (nobody resets it here), which
 * is what makes a quick rematch just a second tap of Start.
 */
export function GameSelector({
  lobbyId,
  code,
  isHost,
  inFlight,
  selectedGame,
  players,
  era = null,
  higherOrLowerEra = null,
}: {
  lobbyId: string;
  code: string;
  isHost: boolean;
  inFlight: boolean;
  selectedGame: MatchGame | null;
  players: number;
  era?: Era | null;
  higherOrLowerEra?: { seasonMin: number; seasonMax: number } | null;
}) {
  const selected = LAUNCHABLE.find((game) => game.match === selectedGame) ?? null;
  // Nothing chosen yet forces the picker open; once something is chosen, the
  // picker only reappears when the host asks to change it.
  const [picking, setPicking] = useState(selected === null);

  return (
    <section aria-labelledby="next-up-heading" className="flex flex-col gap-3">
      <div>
        <p className="type-label text-fg-muted">Next up</p>
        <h2 id="next-up-heading" className="mt-1 font-slab text-2xl leading-none uppercase">
          {selected && !(isHost && picking) ? selected.name.join(" ") : "Choose a game"}
        </h2>
      </div>

      {isHost && picking ? (
        <GamePicker
          lobbyId={lobbyId}
          code={code}
          onCancel={selected ? () => setPicking(false) : undefined}
        />
      ) : selected ? (
        <SelectedGame
          game={selected}
          isHost={isHost}
          inFlight={inFlight}
          onChange={() => setPicking(true)}
        >
          {isHost && !inFlight ? (
            selected.match === "higher_or_lower" ? (
              <StartHigherOrLower lobbyId={lobbyId} code={code} players={players} era={higherOrLowerEra} />
            ) : selected.match === "sabotage_draft" ? (
              <StartSabotageDraft lobbyId={lobbyId} code={code} players={players} />
            ) : selected.match === "wavelength_2v2" ? (
              <StartWavelength lobbyId={lobbyId} code={code} players={players} />
            ) : (
              <StartRun lobbyId={lobbyId} code={code} players={players} era={era} />
            )
          ) : null}
        </SelectedGame>
      ) : (
        <p className="text-sm leading-5 text-fg-muted">The host hasn&apos;t picked a game yet.</p>
      )}
    </section>
  );
}

function SelectedGame({
  game,
  isHost,
  inFlight,
  onChange,
  children,
}: {
  game: (typeof LAUNCHABLE)[number];
  isHost: boolean;
  inFlight: boolean;
  onChange: () => void;
  children: ReactNode;
}) {
  return (
    <Card className="flex flex-col">
      <div className="flex flex-col gap-2 p-3.5">
        <p className="type-label text-hidden-text">
          {game.kind}
        </p>
        <p className="text-sm leading-5 text-panel-soft">{game.tagline}</p>
        <p className="type-label text-panel-muted">
          {game.players}
        </p>
      </div>

      {isHost && !inFlight ? (
        <button
          type="button"
          onClick={onChange}
          className="border-t border-panel-line px-3.5 py-2.5 text-left type-label text-panel-muted transition-colors hover:text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
        >
          Change game
        </button>
      ) : null}

      {children ? <div className="border-t border-panel-line bg-panel-shade p-2.5">{children}</div> : null}

      {!isHost && !inFlight ? (
        <p className="border-t border-panel-line px-3.5 py-2.5 type-label text-panel-muted">
          Waiting for the host to start
        </p>
      ) : null}
    </Card>
  );
}

function GamePicker({
  lobbyId,
  code,
  onCancel,
}: {
  lobbyId: string;
  code: string;
  onCancel?: () => void;
}) {
  return (
    <div className="flex flex-col gap-2">
      <ul className="flex flex-col gap-2">
        {LAUNCHABLE.map((game) => (
          <li key={game.slug}>
            <form action={selectGame}>
              <input type="hidden" name="lobby_id" value={lobbyId} />
              <input type="hidden" name="code" value={code} />
              <input type="hidden" name="game" value={game.match ?? ""} />
              <button
                type="submit"
                className="flex w-full flex-col gap-1 rounded-card bg-panel px-3.5 py-3 text-left text-panel-fg shadow-card transition-colors hover:bg-panel-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
              >
                <span className="font-slab text-lg leading-none uppercase">{game.name.join(" ")}</span>
                <span className="type-label text-panel-muted">
                  {game.players}
                </span>
              </button>
            </form>
          </li>
        ))}
      </ul>

      {onCancel ? (
        <Button type="button" variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
      ) : null}
    </div>
  );
}
