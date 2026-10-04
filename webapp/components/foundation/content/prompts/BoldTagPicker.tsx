"use client";

import { useState } from "react";

import { PlayerPicker } from "./PlayerPicker";
import { MatchupTile, TeamTile } from "./PromptTiles";
import type { NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { TEAMS } from "@/lib/foundation/content/prompts/staticOptionPools";
import type { BoldTarget, BoldTargetType } from "@/lib/foundation/content/prompts/boldPredictions";
import type { PlayerResult, PlayerSearch } from "@/lib/foundation/content/prompts/players";

const MODES: { type: BoldTargetType; label: string }[] = [
  { type: "matchup", label: "Matchup" },
  { type: "team", label: "Team" },
  { type: "player", label: "Player" },
];

type Props = {
  /** The chosen tag, or null. Controlled: the parent owns the selection. */
  value: BoldTarget | null;
  onChange: (target: BoldTarget | null) => void;
  /** That week's games, for the matchup mode. */
  weekGames: NflScheduleGame[];
  /** Directory rows for player tags the parent already knows, by id. */
  players: Record<string, PlayerResult>;
  /** Called with a player the viewer found, so the parent can keep drawing their tag. */
  onPlayerFound: (player: PlayerResult) => void;
  /** Overrides the directory lookup; defaults to prompts.search_players. */
  search?: PlayerSearch;
};

/**
 * Chooses the single required tag on a prediction: a matchup from the week's
 * games, one of the 32 teams, or a player found through the directory search.
 * Switching mode drops a tag of the other kind, so a prediction can never hold
 * two at once.
 */
export function BoldTagPicker({ value, onChange, weekGames, players, onPlayerFound, search }: Props) {
  const [chosenMode, setChosenMode] = useState<BoldTargetType>(value?.type ?? "matchup");
  const mode = value?.type ?? chosenMode;

  function switchMode(next: BoldTargetType) {
    setChosenMode(next);
    if (value && value.type !== next) onChange(null);
  }

  return (
    <div className="flex flex-col gap-3">
      <div role="group" aria-label="Tag type" className="flex flex-wrap gap-1.5">
        {MODES.map(({ type, label }) => (
          <button
            key={type}
            type="button"
            aria-pressed={mode === type}
            onClick={() => switchMode(type)}
            className={`cursor-pointer px-3 py-2 font-slab text-xs uppercase ${mode === type ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
          >
            {label}
          </button>
        ))}
      </div>

      {mode === "matchup" ? (
        weekGames.length ? (
          <div role="group" aria-label="Matchups this week" className="grid gap-2 md:grid-cols-2">
            {weekGames.map((game) => (
              <MatchupTile
                key={game.id}
                away={game.away}
                home={game.home}
                label={game.label}
                pressed={value?.type === "matchup" && value.id === game.id}
                dimmed={value?.type === "matchup" && value.id !== game.id}
                onClick={() => onChange({ type: "matchup", id: game.id })}
              />
            ))}
          </div>
        ) : <p className="text-sm text-fg-muted">No games are scheduled for this week.</p>
      ) : null}

      {mode === "team" ? (
        <div role="group" aria-label="Teams" className="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
          {TEAMS.map((team) => (
            <TeamTile
              key={team.code}
              code={team.code}
              name={team.name}
              pressed={value?.type === "team" && value.id === team.code}
              dimmed={value?.type === "team" && value.id !== team.code}
              onClick={() => onChange({ type: "team", id: team.code })}
            />
          ))}
        </div>
      ) : null}

      {mode === "player" ? (
        <PlayerPicker
          label="Player tag"
          search={search}
          value={value?.type === "player" ? players[value.id] ?? null : null}
          onChange={(player) => {
            if (player) onPlayerFound(player);
            onChange(player ? { type: "player", id: player.id } : null);
          }}
        />
      ) : null}
    </div>
  );
}
