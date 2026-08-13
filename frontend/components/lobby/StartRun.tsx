"use client";

import { useState } from "react";

import { Button } from "@/components/ui/Button";
import { startRun } from "@/lib/lobbies/actions";

/**
 * The era the host may deal from, as `auction.season_bounds()` reports it.
 *
 * All three numbers come from the database rather than from here. The bounds
 * are the pool's own extent — 0007 gave `player_weeks.season` a lower bound and
 * no upper one precisely so a finished season can arrive as a migration, and a
 * year written down in this file would be the thing that could not reach it.
 * The minimum span is the dealer's rule, read rather than restated, so the form
 * cannot offer a range that would be refused.
 */
export type Era = { seasonMin: number; seasonMax: number; minSpan: number };

/**
 * The control that turns a room into a game. Host only, because a game
 * beginning while somebody is still explaining the rules is the thing the
 * host-only check exists to prevent — the RPC enforces it either way, so this
 * is the honest rendering of a rule rather than the rule itself.
 *
 * Disabled below two players, and disabled on a season range the dealer would
 * refuse, with the reason next to it in both cases. The database has its own
 * floor for each and will refuse; saying so before the tap is what stops it
 * reading as a broken button.
 */
export function StartRun({
  lobbyId,
  code,
  players,
  era = null,
}: {
  lobbyId: string;
  code: string;
  players: number;
  era?: Era | null;
}) {
  // Undefined bounds mean the era could not be read. The fields then do not
  // render, the action sends no range, and the dealer resolves the whole pool —
  // which is what every board was dealt from before this was a choice.
  const [from, setFrom] = useState(era?.seasonMin ?? 0);
  const [to, setTo] = useState(era?.seasonMax ?? 0);

  const short = players < 2;
  const backwards = era !== null && to < from;
  const narrow = era !== null && !backwards && to - from + 1 < era.minSpan;
  const reason = short
    ? "Waiting for one more player"
    : backwards
      ? "The last season has to come after the first"
      : narrow
        ? `Pick a span of at least ${era?.minSpan} seasons`
        : null;

  return (
    <form action={startRun} className="flex flex-col gap-2">
      <input type="hidden" name="lobby_id" value={lobbyId} />
      <input type="hidden" name="code" value={code} />
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Scoring
        <select
          aria-label="Scoring"
          name="scoring_mode"
          defaultValue="weekly"
          className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
        >
          <option value="weekly">Weekly</option>
          <option value="season_total">Season total</option>
        </select>
      </label>
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Roster
        <select
          aria-label="Roster"
          name="roster_preset"
          defaultValue="standard"
          className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
        >
          <option value="standard">Standard · 20 lots</option>
          <option value="full">Full · 28 lots</option>
          <option value="deep">Deep · 40 lots</option>
        </select>
      </label>
      {era ? (
        <div className="flex gap-2">
          <label className="flex flex-1 flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
            First season
            <select
              aria-label="First season"
              name="season_from"
              value={from}
              onChange={(event) => setFrom(Number(event.target.value))}
              className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
            >
              {seasons(era).map((season) => (
                <option key={season} value={season}>
                  {season}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-1 flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
            Last season
            <select
              aria-label="Last season"
              name="season_to"
              value={to}
              onChange={(event) => setTo(Number(event.target.value))}
              className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
            >
              {seasons(era).map((season) => (
                <option key={season} value={season}>
                  {season}
                </option>
              ))}
            </select>
          </label>
        </div>
      ) : null}
      <Button type="submit" disabled={short || backwards || narrow}>
        Start the auction
      </Button>
      {reason ? (
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">{reason}</p>
      ) : null}
    </form>
  );
}

function seasons({ seasonMin, seasonMax }: Era): number[] {
  return Array.from({ length: seasonMax - seasonMin + 1 }, (_, i) => seasonMin + i);
}
