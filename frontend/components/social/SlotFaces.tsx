"use client";

import { Check, ChevronDown, ChevronUp, X } from "lucide-react";
import { Fragment, useState } from "react";

import { PlayerPortrait, ProtoTeamLogo } from "./ProtoImages";
import { PROMPT_TICKET_CUT_CORNERS, PromptTicket } from "./PromptTicket";
import { isOptionTakenElsewhere } from "./logic";
import { nflTeamFullName } from "@/lib/nfl/schedule";
import type { Slot } from "./types";

/**
 * PROTOTYPE — throwaway. The slot-input renderers, pulled out of PromptPostUI.tsx
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
  const [away, home] = slot.options;
  return (
    <div className="mt-5 w-full px-4 sm:px-6">
      <PromptTicket className="p-3 sm:p-4">
        <div className="grid w-full grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-stretch gap-2 sm:gap-4">
      {[away, home].map((option, i) => {
        const selected = response[0] === option.id;
        const isCorrect = slot.correct?.includes(option.id);
        const wrongPick = slot.correct && selected && !isCorrect;
        const state = slot.correct
          ? isCorrect
            ? "border-grade-elite bg-grade-elite/10 text-fg"
            : wrongPick
              ? "border-grade-rough bg-grade-rough/10 text-fg"
              : "border-line bg-surface-raised text-fg-muted"
          : selected
            ? "border-panel-fg bg-panel-fg text-panel shadow-[0_10px_22px_rgb(0_0_0/0.2)]"
            : "border-line bg-surface-raised text-fg hover:border-fg hover:bg-surface";
        const label = slot.correct
          ? isCorrect ? "Winner" : wrongPick ? "Your call" : ""
          : selected ? "Your call" : "Pick winner";
        return (
          <Fragment key={option.id}>
            <button
              type="button"
              disabled={disabled}
              aria-pressed={selected}
              onClick={() => onChange([option.id])}
              style={PROMPT_TICKET_CUT_CORNERS}
              className={`${i === 0 ? "col-start-1" : "col-start-3"} row-start-1 flex min-h-48 min-w-0 flex-col items-center justify-between border-2 px-3 py-4 text-center transition-all sm:min-h-56 sm:px-5 sm:py-5 ${state}`}
            >
              <span className="w-full font-mono text-[9px] tracking-[0.14em] uppercase opacity-75">{i === 0 ? "Away" : "Home"}</span>
              <span className="flex flex-col items-center gap-3">
                {option.teamCode ? <ProtoTeamLogo code={option.teamCode} className="h-16 w-16 sm:h-24 sm:w-24" /> : null}
                <span className="font-slab text-lg leading-none uppercase sm:text-2xl">{option.label}</span>
              </span>
              <span className="min-h-3 font-mono text-[9px] tracking-[0.12em] uppercase opacity-80">{label}</span>
            </button>
            {i === 0 ? (
              <span aria-hidden="true" className="col-start-2 row-start-1 flex h-10 w-10 self-center items-center justify-center rounded-full border border-line bg-surface font-slab text-xs text-fg-muted shadow-[0_4px_12px_rgb(0_0_0/0.18)] sm:h-12 sm:w-12 sm:text-sm">
                VS
              </span>
            ) : null}
          </Fragment>
        );
      })}
        </div>
      </PromptTicket>
    </div>
  );
}

/**
 * The compact, read-only result view for a user's winner picks. It deliberately
 * does not reuse GamePickFace: choices need big tap targets, while completed
 * calls need to be scanned across an entire weekly slate. One ticket-style
 * card holds the whole slate — each game a row divided by a hairline rather
 * than its own card, so a full week's calls stay single-column and scannable
 * without ever needing a second column to fit.
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
      <PromptTicket className="divide-y divide-dashed divide-line md:grid md:grid-cols-2 md:divide-y-0">
        {visibleSlots.map((slot) => {
          const [away, home] = slot.options;
          const calledId = responses[slot.id]?.[0];
          const winnerId = slot.correct?.[0];
          const correct = resolved && calledId === winnerId;
          const picked = slot.options.find((option) => option.id === calledId);
          const awayName = away.teamCode ? nflTeamFullName(away.teamCode) : away.label;
          const homeName = home.teamCode ? nflTeamFullName(home.teamCode) : home.label;

          return (
            <div key={slot.id} className="flex items-center justify-between gap-3 px-3 py-2 md:border-b md:border-dashed md:border-line sm:px-4">
              <p className="min-w-0 flex-1 truncate font-mono text-[11px] leading-tight font-medium text-fg-muted sm:text-xs">{awayName} <span>@</span> {homeName}</p>
              <div className="flex shrink-0 items-center gap-2">
                {picked ? <OptionIcon option={picked} className="h-7 w-7" /> : null}
                <span className="font-slab text-lg leading-none uppercase">{picked?.teamCode ?? picked?.label ?? "—"}</span>
                {resolved ? correct ? <Check aria-label="Correct" className="h-5 w-5 text-grade-elite" strokeWidth={3} /> : <X aria-label="Incorrect" className="h-5 w-5 text-grade-rough" strokeWidth={3} /> : null}
              </div>
            </div>
          );
        })}
      </PromptTicket>
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
        {slots.map((slot) => {
          const [away, home] = slot.options;
          const selected = responses[slot.id]?.[0];
          return (
            <div key={slot.id} className="border border-line bg-surface">
              <p className="truncate border-b border-line px-2.5 py-1.5 font-mono text-[9px] tracking-[0.06em] text-fg-muted uppercase">{slot.label}</p>
              <div className="grid grid-cols-2 divide-x divide-line">
                {[away, home].map((option, index) => {
                  const picked = selected === option.id;
                  return (
                    <button
                      key={option.id}
                      type="button"
                      onClick={() => onChange(slot.id, [option.id])}
                      className={`flex min-w-0 items-center gap-2 px-2.5 py-2 text-left transition-colors ${picked ? "bg-panel-fg text-panel" : "text-fg hover:bg-surface-raised"}`}
                      aria-pressed={picked}
                    >
                      {option.teamCode ? <ProtoTeamLogo code={option.teamCode} className="h-6 w-6 shrink-0" /> : null}
                      <span className="min-w-0 truncate font-slab text-xs uppercase">{option.teamCode ?? option.label}</span>
                      <span className="ml-auto shrink-0 font-mono text-[8px] tracking-[0.08em] opacity-65 uppercase">{index === 0 ? "Away" : "Home"}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          );
        })}
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
      {option.teamCodes.map((code) => <ProtoTeamLogo key={code} code={code} className={className} />)}
    </span>
  );
  if (option.teamCode) return <ProtoTeamLogo code={option.teamCode} className={className} />;
  return null;
}
