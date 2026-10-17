"use client";

import { Select } from "@/components/foundation/ui-kit/Select";

/**
 * The era a solo Higher or Lower ladder is dealt from: a first and a last
 * season, sent as `season_from` / `season_to`.
 *
 * Moving either end past the other drags the other along, so the pair can
 * never be backwards — the same rule iOS's picker keeps. That is a courtesy;
 * whether the range is deep enough to deal from is the dealer's to refuse
 * (`higher_or_lower.start`), not re-decided here.
 *
 * Controlled, because it lives in a dialog that unmounts when shut: the card
 * owns the pick so it survives, and sends it with the form.
 */
export function SoloSeasonRange({
  era,
  from,
  to,
  onChange,
}: {
  era: { seasonMin: number; seasonMax: number };
  from: number;
  to: number;
  onChange: (range: { from: number; to: number }) => void;
}) {
  const seasons = Array.from({ length: era.seasonMax - era.seasonMin + 1 }, (_, index) => era.seasonMin + index);
  const options = seasons.map((season) => ({ value: String(season), label: season }));

  return (
    <fieldset className="mb-3 flex flex-col gap-1.5">
      <legend className="mb-1.5 type-label-xs font-semibold text-fg-muted">
        Era
      </legend>
      <div className="flex gap-2">
        <label className="flex flex-1 flex-col gap-1 type-label-xs text-fg-muted">
          First season
          <Select
            variant="dark"
            ariaLabel="First season"
            name="season_from"
            value={String(from)}
            onValueChange={(next) => {
              onChange({ from: Number(next), to: Math.max(to, Number(next)) });
            }}
            options={options}
          />
        </label>
        <label className="flex flex-1 flex-col gap-1 type-label-xs text-fg-muted">
          Last season
          <Select
            variant="dark"
            ariaLabel="Last season"
            name="season_to"
            value={String(to)}
            onValueChange={(next) => {
              onChange({ from: Math.min(from, Number(next)), to: Number(next) });
            }}
            options={options}
          />
        </label>
      </div>
    </fieldset>
  );
}
