"use client";

import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Select } from "@/components/foundation/ui-kit/Select";
import { startRun } from "@/lib/platform/lobbies/actions";

/**
 * The control that deals a Higher or Lower ladder.
 *
 * No format fields yet, deliberately. The two the host will eventually pick —
 * scoring mode and era window — are arguments of the start RPC already, and it
 * resolves them to season total over the whole pool when they are absent. The
 * picker is #29; sending nothing until then is a validated choice rather than
 * an unchecked path.
 *
 * Rendered for the host only, because a game beginning while somebody is still
 * explaining the rules is what the host-only rule exists to prevent. The rule
 * itself is `public.start_run`, which refuses anybody but the room's host;
 * `higher_or_lower.start` then checks that its caller is in the run. So this is
 * the honest rendering of a rule enforced upstream, not the rule.
 */
export function StartHigherOrLower({
  lobbyId,
  code,
  players,
  era,
}: {
  lobbyId: string;
  code: string;
  players: number;
  era: { seasonMin: number; seasonMax: number } | null;
}) {
  const short = players < 2;
  const [from, setFrom] = useState(era?.seasonMin ?? 0);
  const [to, setTo] = useState(era?.seasonMax ?? 0);
  const backwards = era !== null && to < from;

  return (
    <form action={startRun} className="flex flex-col gap-2">
      <input type="hidden" name="lobby_id" value={lobbyId} />
      <input type="hidden" name="code" value={code} />
      <input type="hidden" name="game" value="higher_or_lower" />
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Scoring
        <Select
          ariaLabel="Scoring"
          name="scoring_mode"
          defaultValue="season_total"
          options={[
            { value: "season_total", label: "Season total" },
            { value: "weekly", label: "Weekly PPR" },
          ]}
        />
      </label>
      {era ? <div className="flex gap-2">
        <Season label="First season" name="season_from" value={from} era={era} onChange={setFrom} />
        <Season label="Last season" name="season_to" value={to} era={era} onChange={setTo} />
      </div> : null}
      <Button type="submit" disabled={short || backwards}>
        Start higher or lower
      </Button>
      {short ? (
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          Waiting for one more player
        </p>
      ) : null}
      {backwards ? (
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          The last season has to come after the first
        </p>
      ) : null}
    </form>
  );
}

function Season({ label, name, value, era, onChange }: { label: string; name: string; value: number; era: { seasonMin: number; seasonMax: number }; onChange: (value: number) => void }) {
  const seasons = Array.from({ length: era.seasonMax - era.seasonMin + 1 }, (_, index) => era.seasonMin + index);
  return <label className="flex flex-1 flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">{label}
    <Select
      ariaLabel={label}
      name={name}
      value={String(value)}
      onValueChange={(next) => onChange(Number(next))}
      options={seasons.map((season) => ({ value: String(season), label: season }))}
    />
  </label>;
}
