"use client";

import { useState, type ReactNode } from "react";

import { StartHigherOrLower } from "@/components/lobby/StartHigherOrLower";
import { StartRun, type Era } from "@/components/lobby/StartRun";
import { StartSabotageDraft } from "@/components/lobby/StartSabotageDraft";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { GAMES, type MatchGame } from "@/lib/games/catalog";
import { selectGame } from "@/lib/lobbies/actions";

const LAUNCHABLE = GAMES.filter((game) => game.match !== null);

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
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">Next up</p>
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
        <p className="font-mono text-[10px] tracking-[0.13em] text-hidden-ink uppercase">
          {game.kind}
        </p>
        <p className="text-sm leading-5 text-[#4c4739]">{game.tagline}</p>
        <p className="font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
          {game.players}
        </p>
      </div>

      {isHost && !inFlight ? (
        <button
          type="button"
          onClick={onChange}
          className="border-t border-[#c7bfac] px-3.5 py-2.5 text-left font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase transition-colors hover:text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
        >
          Change game
        </button>
      ) : null}

      {children ? <div className="border-t border-[#c7bfac] bg-panel-shade p-2.5">{children}</div> : null}

      {!isHost && !inFlight ? (
        <p className="border-t border-[#c7bfac] px-3.5 py-2.5 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
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
                className="flex w-full flex-col gap-1 rounded-card bg-panel px-3.5 py-3 text-left text-panel-fg shadow-card transition-colors hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
              >
                <span className="font-slab text-lg leading-none uppercase">{game.name.join(" ")}</span>
                <span className="font-mono text-[10px] tracking-[0.11em] text-panel-muted uppercase">
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
