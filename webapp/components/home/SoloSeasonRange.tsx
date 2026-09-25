"use client";

import { useState } from "react";

import { Select } from "@/components/foundation/ui-kit/Select";

/**
 * The era a solo Higher or Lower ladder is dealt from: a first and a last
 * season, sent as `season_from` / `season_to`.
 *
 * Moving either end past the other drags the other along, so the pair can
 * never be backwards — the same rule iOS's picker keeps. That is a courtesy;
 * whether the range is deep enough to deal from is the dealer's to refuse
 * (`higher_or_lower.start`), not re-decided here.
 */
export function SoloSeasonRange({ era }: { era: { seasonMin: number; seasonMax: number } }) {
  const [from, setFrom] = useState(era.seasonMin);
  const [to, setTo] = useState(era.seasonMax);
  const seasons = Array.from({ length: era.seasonMax - era.seasonMin + 1 }, (_, index) => era.seasonMin + index);
  const options = seasons.map((season) => ({ value: String(season), label: season }));

  return (
    <fieldset className="mb-3 flex flex-col gap-1.5">
      <legend className="mb-1.5 font-mono text-[9px] font-semibold tracking-[0.1em] text-fg-muted uppercase">
        Era
      </legend>
      <div className="flex gap-2">
        <label className="flex flex-1 flex-col gap-1 font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">
          First season
          <Select
            variant="dark"
            ariaLabel="First season"
            name="season_from"
            value={String(from)}
            onValueChange={(next) => {
              setFrom(Number(next));
              if (Number(next) > to) setTo(Number(next));
            }}
            options={options}
          />
        </label>
        <label className="flex flex-1 flex-col gap-1 font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">
          Last season
          <Select
            variant="dark"
            ariaLabel="Last season"
            name="season_to"
            value={String(to)}
            onValueChange={(next) => {
              setTo(Number(next));
              if (Number(next) < from) setFrom(Number(next));
            }}
            options={options}
          />
        </label>
      </div>
    </fieldset>
  );
}
