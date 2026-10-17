"use client";

import { Settings } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import type { SoloMode } from "@/lib/platform/orchestration/catalog";
import { SoloSeasonRange } from "./SoloSeasonRange";

/** One start-time choice: radios sent under `name`; the first option is the default. */
export type SoloChoice = { name: string; legend: string; options: readonly SoloMode[] };

/**
 * The bottom of a solo card: Play solo beside a settings button. It sits in the
 * card's form and renders the card's picks as hidden inputs, because the
 * dialog the picks are made in is portaled out of the form (and unmounts when
 * shut). A card with nothing to choose gets no settings button.
 */
export function SoloPlayControls({
  title,
  choices,
  era,
}: {
  title: string;
  choices: readonly SoloChoice[];
  era: { seasonMin: number; seasonMax: number } | null;
}) {
  const [open, setOpen] = useState(false);
  const [picks, setPicks] = useState<Record<string, string>>(() =>
    Object.fromEntries(choices.map((choice) => [choice.name, choice.options[0].value])),
  );
  const [range, setRange] = useState(() => (era ? { from: era.seasonMin, to: era.seasonMax } : null));
  const hasSettings = choices.length > 0 || era !== null;

  return (
    <>
      {Object.entries(picks).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {range ? (
        <>
          <input type="hidden" name="season_from" value={range.from} />
          <input type="hidden" name="season_to" value={range.to} />
        </>
      ) : null}

      <div className="flex gap-2">
        <Button size="sm" type="submit" className="flex-1">
          Play
        </Button>
        {hasSettings ? (
          <Button
            size="sm"
            type="button"
            variant="ghost"
            fullWidth={false}
            aria-label={`${title} settings`}
            onClick={() => setOpen(true)}
            className="flex w-9 items-center justify-center px-0"
          >
            <Settings aria-hidden className="h-4 w-4" strokeWidth={1.75} />
          </Button>
        ) : null}
      </div>

      {open ? (
        <Modal onClose={() => setOpen(false)} closeLabel={`Close ${title} settings`} size="sm">
          <ModalTitle className="pr-10 font-slab text-xl leading-[1.04] uppercase">{title} settings</ModalTitle>
          <div className="mt-4">
            {choices.map((choice) => (
              <fieldset key={choice.name} className="mb-3 flex flex-col gap-1.5">
                <legend className="mb-1.5 type-label-xs font-semibold text-fg-muted">{choice.legend}</legend>
                {choice.options.map((option) => (
                  <label
                    key={option.value}
                    className="flex cursor-pointer items-start gap-2 rounded-chip border border-line px-2.5 py-2 transition-colors has-checked:border-fg has-checked:bg-surface has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-fg"
                  >
                    <input
                      type="radio"
                      name={`setting-${choice.name}`}
                      value={option.value}
                      checked={picks[choice.name] === option.value}
                      onChange={() => setPicks((current) => ({ ...current, [choice.name]: option.value }))}
                      className="mt-0.5 accent-current"
                    />
                    <span className="flex flex-col">
                      <span className="type-label-lg font-bold">{option.label}</span>
                      <span className="text-[12px] leading-4 text-fg-muted">{option.description}</span>
                    </span>
                  </label>
                ))}
              </fieldset>
            ))}
            {era && range ? <SoloSeasonRange era={era} from={range.from} to={range.to} onChange={setRange} /> : null}
          </div>
          <Button size="sm" type="button" onClick={() => setOpen(false)}>
            Done
          </Button>
        </Modal>
      ) : null}
    </>
  );
}
