"use client";

import { Check, ChevronDown, ChevronUp, X } from "lucide-react";
import { Fragment } from "react";

import { PlayerPortrait, ProtoTeamLogo } from "./ProtoImages";
import { isOptionTakenElsewhere } from "./logic";
import { nflTeamFullName } from "@/lib/nfl/schedule";
import type { Slot } from "./types";

/**
 * PROTOTYPE — throwaway. The slot-input renderers, pulled out of VariantC.tsx
 * so both the feed card's result mode and the dedicated answer screen
 * (PostAnswerScreen) can render identical slot UI without either importing
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
              className={`${i === 0 ? "col-start-1" : "col-start-3"} row-start-1 flex min-h-48 min-w-0 flex-col items-center justify-between rounded-2xl border-2 px-3 py-4 text-center transition-all sm:min-h-56 sm:px-5 sm:py-5 ${state}`}
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
}: {
  slots: Slot[];
  responses: Record<string, string[]>;
  resolved: boolean;
}) {
  return (
    <section className="mt-4 px-4" aria-label="Your calls">
      <div
        className="overflow-hidden bg-surface divide-y divide-dashed divide-line"
        style={{ clipPath: "polygon(24px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 24px) 100%, 0 100%, 0 14px)" }}
      >
        {slots.map((slot) => {
          const [away, home] = slot.options;
          const calledId = responses[slot.id]?.[0];
          const winnerId = slot.correct?.[0];
          const correct = resolved && calledId === winnerId;
          const picked = slot.options.find((option) => option.id === calledId);
          const awayName = away.teamCode ? nflTeamFullName(away.teamCode) : away.label;
          const homeName = home.teamCode ? nflTeamFullName(home.teamCode) : home.label;

          return (
            <div key={slot.id} className="flex items-center justify-between gap-3 px-3 py-2 sm:px-4">
              <p className="min-w-0 flex-1 truncate font-mono text-[11px] leading-tight font-medium text-fg-muted sm:text-xs">{awayName} <span>@</span> {homeName}</p>
              <div className="flex shrink-0 items-center gap-2">
                {picked ? <OptionIcon option={picked} className="h-7 w-7" /> : null}
                <span className="font-slab text-lg leading-none uppercase">{picked?.teamCode ?? picked?.label ?? "—"}</span>
                {resolved ? correct ? <Check aria-label="Correct" className="h-5 w-5 text-grade-elite" strokeWidth={3} /> : <X aria-label="Incorrect" className="h-5 w-5 text-grade-rough" strokeWidth={3} /> : null}
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
