"use client";

import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Select } from "@/components/foundation/ui-kit/Select";
import { startRun } from "@/lib/platform/lobbies/actions";

type WavelengthMode = "coop" | "versus";

const PRESETS = [
  { value: "short", label: "Short · 4 rounds · target 8" },
  { value: "medium", label: "Medium · 6 rounds · target 12" },
  { value: "long", label: "Long · 8 rounds · target 20" },
] as const;

/**
 * Wavelength's roster is part of its format: co-op has one pair and 2v2 has
 * two. The platform can freeze any two-to-four-player lobby, so this control
 * says which of those counts the dealer will accept before it opens a match.
 */
export function StartWavelength({ lobbyId, code, players }: { lobbyId: string; code: string; players: number }) {
  const [mode, setMode] = useState<WavelengthMode>("coop");
  const requiredPlayers = mode === "coop" ? 2 : 4;
  const countMismatch = players !== requiredPlayers;
  const modeLabel = mode === "coop" ? "Co-op" : "2v2";

  return (
    <form action={startRun} className="flex flex-col gap-2">
      <input type="hidden" name="lobby_id" value={lobbyId} />
      <input type="hidden" name="code" value={code} />
      <input type="hidden" name="game" value="wavelength_2v2" />
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Mode
        <Select
          ariaLabel="Mode"
          name="wavelength_mode"
          value={mode}
          onValueChange={(value) => setMode(value as WavelengthMode)}
          options={[
            { value: "coop", label: "Co-op" },
            { value: "versus", label: "2v2" },
          ]}
        />
      </label>
      {mode === "coop" ? (
        <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
          Game length
          <Select ariaLabel="Game length" name="wavelength_preset" defaultValue="short" options={[...PRESETS]} />
        </label>
      ) : null}
      <Button type="submit" disabled={countMismatch}>Start Wavelength</Button>
      {countMismatch ? (
        <p className="font-mono text-[10px] tracking-[.13em] text-fg-muted uppercase">
          {modeLabel} needs exactly {requiredPlayers} players (you have {players})
        </p>
      ) : null}
    </form>
  );
}
