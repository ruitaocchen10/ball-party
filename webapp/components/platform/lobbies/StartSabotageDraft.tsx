"use client";

import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Select } from "@/components/foundation/ui-kit/Select";
import { startRun } from "@/lib/platform/lobbies/actions";
import { GAME_MODES, MODE_LABELS, type GameMode } from "@/lib/games/sabotage-draft/rounds";

export function StartSabotageDraft({ lobbyId, code, players }: { lobbyId: string; code: string; players: number }) {
  const short = players < 2;
  const [mode, setMode] = useState<GameMode>("full");
  return <form action={startRun} className="flex flex-col gap-2">
    <input type="hidden" name="lobby_id" value={lobbyId} />
    <input type="hidden" name="code" value={code} />
    <input type="hidden" name="game" value="sabotage_draft" />
    <label className="flex flex-col gap-1 type-label text-panel-muted">
      Mode
      <Select
        ariaLabel="Mode"
        name="draft_mode"
        value={mode}
        onValueChange={value => setMode(value as GameMode)}
        options={GAME_MODES.map(value => ({ value, label: MODE_LABELS[value].name }))}
      />
    </label>
    <p className="text-xs leading-4 text-panel-muted normal-case">{MODE_LABELS[mode].blurb}</p>
    <Button type="submit" disabled={short}>Start sabotage draft</Button>
    {short ? <p className="type-label text-fg-muted">Waiting for one more player</p> : null}
  </form>;
}
