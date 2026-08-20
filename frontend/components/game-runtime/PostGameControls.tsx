"use client";

import { useState } from "react";

import { Button } from "@/components/ui/Button";
import type { AuctionFormat } from "@/lib/auction/board";
import { postGameChoice } from "@/lib/lobbies/actions";

type Era = { seasonMin: number; seasonMax: number; minSpan: number };

/** The host advances the shared room; everybody else can keep reading results. */
export function PostGameControls({
  matchId,
  roomCode,
  isHost,
  format = null,
  era = null,
}: {
  matchId: string;
  roomCode: string;
  isHost: boolean;
  format?: AuctionFormat | null;
  era?: Era | null;
}) {
  const [configuringReplay, setConfiguringReplay] = useState(false);
  const [from, setFrom] = useState(format?.seasonFrom ?? era?.seasonMin ?? 0);
  const [to, setTo] = useState(format?.seasonTo ?? era?.seasonMax ?? 0);

  if (!isHost) {
    return <p className="text-sm text-fg-muted">Waiting for the host to choose what’s next.</p>;
  }

  const backwards = era !== null && to < from;
  const replayDisabled = backwards;
  const reason = backwards
    ? "The last season has to come after the first"
    : null;

  return (
    <div className="mt-2 flex flex-col gap-2">
      {configuringReplay ? (
        <form action={postGameChoice} className="flex flex-col gap-2 rounded border border-line bg-surface-raised p-3">
          <p className="font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">Next auction settings</p>
          {format ? (
            <>
              <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
                Scoring
                <select aria-label="Scoring" name="scoring_mode" defaultValue={format.scoringMode} className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case">
                  <option value="weekly">Weekly</option>
                  <option value="season_total">Season total</option>
                </select>
              </label>
              <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
                Roster
                <select aria-label="Roster" name="roster_preset" defaultValue={format.rosterPreset} className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case">
                  <option value="standard">Standard · 20 lots</option>
                  <option value="full">Full · 28 lots</option>
                  <option value="deep">Deep · 40 lots</option>
                </select>
              </label>
            </>
          ) : null}
          {era ? (
            <div className="flex gap-2">
              <SeasonSelect label="First season" name="season_from" era={era} value={from} onChange={setFrom} />
              <SeasonSelect label="Last season" name="season_to" era={era} value={to} onChange={setTo} />
            </div>
          ) : null}
          <input type="hidden" name="match_id" value={matchId} />
          <input type="hidden" name="room_code" value={roomCode} />
          <input type="hidden" name="choice" value="replay" />
          <Button type="submit" disabled={replayDisabled} fullWidth>Start replay</Button>
          {reason ? <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">{reason}</p> : null}
        </form>
      ) : (
        <Button type="button" onClick={() => setConfiguringReplay(true)} fullWidth>Replay</Button>
      )}
      <form action={postGameChoice}>
        <input type="hidden" name="match_id" value={matchId} />
        <input type="hidden" name="room_code" value={roomCode} />
        <input type="hidden" name="choice" value="lobby" />
        <Button type="submit" variant="ghost" fullWidth>Back to lobby</Button>
      </form>
    </div>
  );
}

function SeasonSelect({
  label,
  name,
  era,
  value,
  onChange,
}: {
  label: string;
  name: string;
  era: Era;
  value: number;
  onChange: (season: number) => void;
}) {
  return (
    <label className="flex flex-1 flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
      {label}
      <select aria-label={label} name={name} value={value} onChange={(event) => onChange(Number(event.target.value))} className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case">
        {Array.from({ length: era.seasonMax - era.seasonMin + 1 }, (_, i) => era.seasonMin + i).map((season) => (
          <option key={season} value={season}>{season}</option>
        ))}
      </select>
    </label>
  );
}
