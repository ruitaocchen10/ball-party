"use client";

import { ChevronDown, ChevronUp } from "lucide-react";
import { useState } from "react";

import { PlayerPortrait } from "./PlayerPortrait";
import { PromptTeamLogo } from "./PromptTeamLogo";
import { MatchupPicker } from "./MatchupPicker";
import { isOptionTakenElsewhere } from "@/lib/foundation/content/prompts/logic";
import type { Slot } from "@/lib/foundation/content/prompts/types";

/**
 * The slot-input renderers, pulled out of PromptPostUI.tsx
 * so both the feed card's result mode and the dedicated answer screen
 * (the prompt answer route) can render identical slot UI without either importing
 * from the other.
 */
export function GamePickFace({
  slot,
  disabled,
  response,
  onChange,
}: {
  slot: Slot;
  disabled: boolean;
  response: string[];
  onChange: (r: string[]) => void;
}) {
  return (
    <MatchupPicker slot={slot} response={response} onChange={disabled ? undefined : onChange} variant="featured" mode="picker" />
  );
}

/**
 * The read-only result view for winner picks. A matchup grid keeps a whole
 * slate scannable and shareable, while its two-column shape holds even on
 * narrow screens by scaling the team marks down instead of collapsing rows.
 */
export function YourCalls({
  slots,
  responses,
  resolved,
  collapsible = false,
}: {
  slots: Slot[];
  responses: Record<string, string[]>;
  resolved: boolean;
  /** Large weekly tickets start compact; a single-game take never needs this. */
  collapsible?: boolean;
}) {
  const [expanded, setExpanded] = useState(!collapsible || slots.length <= 4);
  const visibleSlots = expanded ? slots : slots.slice(0, 4);
  const hiddenCount = slots.length - visibleSlots.length;
  return (
    <section className="mt-4 px-4" aria-label="Your calls">
      <div className="grid grid-cols-2 gap-2 sm:gap-3">
        {visibleSlots.map((slot) => (
          <MatchupPicker key={slot.id} slot={slot} response={responses[slot.id] ?? []} resolved={resolved} variant="compact" mode="revealed" />
        ))}
      </div>
      {hiddenCount > 0 ? (
        <button
          type="button"
          onClick={() => setExpanded(true)}
          className="mt-2 inline-flex items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg"
        >
          <ChevronDown className="h-3.5 w-3.5" /> View all {slots.length} picks
        </button>
      ) : collapsible && slots.length > 4 ? (
        <button
          type="button"
          onClick={() => setExpanded(false)}
          className="mt-2 inline-flex items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg"
        >
          <ChevronUp className="h-3.5 w-3.5" /> Show fewer picks
        </button>
      ) : null}
    </section>
  );
}

/**
 * A weekly pick sheet: deliberately compact and scan-first. The large
 * GamePickFace remains the focused, single-matchup experience above.
 */
export function GamePickList({
  slots,
  responses,
  onChange,
}: {
  slots: Slot[];
  responses: Record<string, string[]>;
  onChange: (slotId: string, response: string[]) => void;
}) {
  return (
    <section className="px-4 pt-5" aria-label="Weekly pick sheet">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">Make each call</p>
        <p className="font-mono text-[10px] tracking-[0.08em] text-fg-muted tabular-nums uppercase">
          {slots.filter((slot) => responses[slot.id]?.length).length}/{slots.length} picked
        </p>
      </div>
      <div className="grid gap-2 md:grid-cols-2">
        {slots.map((slot) => (
          <MatchupPicker key={slot.id} slot={slot} response={responses[slot.id] ?? []} onChange={(response) => onChange(slot.id, response)} variant="compact" mode="picker" />
        ))}
      </div>
    </section>
  );
}

export function SlotFaceC({
  slot,
  disabled,
  response,
  onChange,
  allResponses,
}: {
  slot: Slot;
  disabled: boolean;
  response: string[];
  onChange: (r: string[]) => void;
  allResponses: Record<string, string[]>;
}) {
  const max = slot.shape === "pick_set" ? (slot.pickCount ?? 1) : slot.shape === "rank" ? (slot.pickCount ?? slot.options.length) : 1;

  if (slot.shape === "rank") {
    const order = response;
    function move(index: number, dir: -1 | 1) {
      const next = [...order];
      const target = index + dir;
      if (target < 0 || target >= next.length) return;
      [next[index], next[target]] = [next[target], next[index]];
      onChange(next);
    }
    return (
      <div>
        <p className="mb-1.5 font-slab text-sm uppercase text-fg-muted">{slot.label} · rank {max} of {slot.options.length}</p>
        <ol className="flex flex-col gap-1.5">
          {order.map((id, i) => {
            const option = slot.options.find((o) => o.id === id)!;
            const isCorrectPosition = slot.correct?.[i] === id;
            return (
              <li
                key={id}
                className={`flex items-center gap-2.5 rounded border-2 px-2.5 py-2 ${
                  slot.correct ? (isCorrectPosition ? "border-grade-elite" : "border-grade-rough") : "border-line bg-surface"
                }`}
              >
                <span className="font-slab text-lg text-fg-muted">{i + 1}</span>
                <OptionIcon option={option} className="h-6 w-6" />
                <span className="flex-1 font-slab text-sm uppercase">{option.label}</span>
                {!disabled ? (
                  <span className="flex shrink-0 gap-1">
                    <button type="button" disabled={i === 0} onClick={() => move(i, -1)} className="disabled:opacity-30">
                      <ChevronUp className="h-4 w-4" />
                    </button>
                    <button type="button" disabled={i === order.length - 1} onClick={() => move(i, 1)} className="disabled:opacity-30">
                      <ChevronDown className="h-4 w-4" />
                    </button>
                  </span>
                ) : slot.correct ? (
                  <span className="shrink-0 font-mono text-[9px] font-bold uppercase">actual #{slot.correct.indexOf(id) + 1}</span>
                ) : null}
              </li>
            );
          })}
        </ol>
        {!disabled && order.length < max ? (
          <div className="mt-2 grid grid-cols-2 gap-1.5 sm:grid-cols-3">
            {slot.options.filter((option) => !order.includes(option.id)).map((option) => (
              <button
                key={option.id}
                type="button"
                onClick={() => onChange([...order, option.id])}
                className="flex items-center gap-2 rounded border border-line bg-surface px-2 py-2 text-left"
              >
                <OptionIcon option={option} className="h-5 w-5" />
                <span className="min-w-0 truncate font-slab text-xs uppercase">{option.label}</span>
              </button>
            ))}
          </div>
        ) : null}
      </div>
    );
  }

  function toggle(id: string) {
    if (disabled) return;
    if (response.includes(id)) {
      onChange(response.filter((r) => r !== id));
      return;
    }
    if (slot.shape === "pick") {
      onChange([id]);
      return;
    }
    if (response.length >= max) return;
    onChange([...response, id]);
  }

  return (
    <div>
      <p className="mb-1.5 font-slab text-sm uppercase text-fg-muted">
        {slot.label}
        {slot.shape === "pick_set" ? ` · ${response.length}/${max}` : ""}
      </p>
      <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
        {slot.options.map((option) => {
          const taken = isOptionTakenElsewhere(slot, option.id, allResponses);
          const selected = response.includes(option.id);
          const isCorrect = slot.correct?.includes(option.id);
          const wrongPick = slot.correct && selected && !isCorrect;
          return (
            <button
              key={option.id}
              type="button"
              disabled={disabled || (taken && !selected)}
              onClick={() => toggle(option.id)}
              className={`flex flex-col items-center gap-1 rounded border-2 px-2 py-2 disabled:opacity-40 ${
                slot.correct
                  ? isCorrect
                    ? "border-grade-elite"
                    : wrongPick
                      ? "border-grade-rough"
                      : "border-transparent bg-surface"
                  : selected
                    ? "border-fg bg-surface"
                    : "border-line bg-surface-raised"
              }`}
            >
              <OptionIcon option={option} className="h-7 w-7" />
              <span className="font-slab text-[11px] uppercase">{option.label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** A player headshot when the option has one, else its team's logo, else nothing. */
export function OptionIcon({ option, className }: { option: Slot["options"][number]; className: string }) {
  if (option.headshotUrl) return <PlayerPortrait name={option.label} headshotUrl={option.headshotUrl} className={className} />;
  if (option.teamCodes) return (
    <span className="flex -space-x-1.5">
      {option.teamCodes.map((code) => <PromptTeamLogo key={code} code={code} className={className} />)}
    </span>
  );
  if (option.teamCode) return <PromptTeamLogo code={option.teamCode} className={className} />;
  return null;
}
