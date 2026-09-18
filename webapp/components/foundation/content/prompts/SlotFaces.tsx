"use client";

import { ChevronDown, ChevronUp } from "lucide-react";
import { useState, type DragEvent } from "react";

import { PlayerPortrait } from "./PlayerPortrait";
import { PromptTeamLogo } from "./PromptTeamLogo";
import { MatchupPicker } from "./MatchupPicker";
import { PROMPT_TICKET_CUT_CORNERS } from "./PromptTicket";
import { isOptionTakenElsewhere } from "@/lib/foundation/content/prompts/logic";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
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

/**
 * Power Rankings keeps the league pool visible while a respondent chooses
 * their own top-N. Native drag events avoid another interaction dependency;
 * the click-to-add controls make the same workflow work on touch devices.
 */
export function PowerRankingsSlot({
  slot,
  response,
  onChange,
  previousRankByTeam,
  disabled = false,
  showEditorHeader = true,
}: {
  slot: Slot;
  response: string[];
  onChange: (response: string[]) => void;
  previousRankByTeam: Record<string, number>;
  disabled?: boolean;
  /** Completed take cards show only the saved board, not editor controls. */
  showEditorHeader?: boolean;
}) {
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [dropTargetIndex, setDropTargetIndex] = useState<number | null>(null);
  // The setting controls the visible board independently of how many teams
  // have been chosen. Empty, numbered slots make the remaining work clear.
  const [rankCount, setSelectedRankCount] = useState<5 | 10 | 32>(() => response.length > 10 ? 32 : response.length > 5 ? 10 : 5);
  // Unlike the persisted response (which is a compact, ordered array), this
  // board keeps empty positions so a team can be dropped directly at #8.
  const [placements, setPlacements] = useState<(string | null)[]>(() => {
    const initialCount = response.length > 10 ? 32 : response.length > 5 ? 10 : 5;
    return Array.from({ length: initialCount }, (_, index) => response[index] ?? null);
  });
  const ranked = placements.filter((id): id is string => id !== null);
  const unranked = slot.options.filter((option) => !ranked.includes(option.id));
  const fullLeagueBoard = rankCount === 32;
  const tenTeamBoard = rankCount === 10;

  function updatePlacements(next: (string | null)[]) {
    setPlacements(next);
    // Once every displayed position is full this preserves exact rank order
    // for submission; until then the compact draft simply stays incomplete.
    onChange(next.filter((id): id is string => id !== null));
  }

  function setRankCount(nextCount: 5 | 10 | 32) {
    setSelectedRankCount(nextCount);
    const next = Array.from({ length: nextCount }, (_, index) => placements[index] ?? null);
    setPlacements(next);
    // Growing only adds empty UI slots; it doesn't change the draft. Shrinking
    // can discard a placed team, so that case must update the response.
    if (nextCount < placements.length) onChange(next.filter((id): id is string => id !== null));
  }

  function moveTo(index: number) {
    if (!draggedId) return;
    const next = [...placements];
    const fromIndex = next.indexOf(draggedId);
    const displacedId = next[index];
    if (fromIndex === index) {
      setDraggedId(null);
      setDropTargetIndex(null);
      return;
    }
    next[index] = draggedId;
    if (fromIndex >= 0) next[fromIndex] = displacedId;
    // An available team replacing a rank sends the displaced club straight
    // back to the available pool (it is simply no longer in placements).
    updatePlacements(next);
    setDraggedId(null);
    setDropTargetIndex(null);
  }

  function onDrop(event: DragEvent<HTMLElement>, index: number) {
    event.preventDefault();
    event.stopPropagation();
    moveTo(index);
  }

  function returnToAvailable(event: DragEvent<HTMLElement>) {
    event.preventDefault();
    event.stopPropagation();
    if (!draggedId) return;
    const index = placements.indexOf(draggedId);
    if (index >= 0) updatePlacements(placements.map((id, candidateIndex) => candidateIndex === index ? null : id));
    setDraggedId(null);
    setDropTargetIndex(null);
  }

  return (
    <section aria-label="Your power rankings">
      {showEditorHeader ? (
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="font-slab text-2xl uppercase">Your power rankings</p>
            <p className="font-mono text-xs text-fg-muted">Drag teams into order. Choose how deep you want to go.</p>
          </div>
          <div className="flex shrink-0 gap-1" aria-label="Number of teams to rank">
            {([5, 10, 32] as const).map((count) => (
              <button key={count} type="button" disabled={disabled} onClick={() => setRankCount(count)} className={`px-2.5 py-2 font-mono text-[10px] uppercase disabled:cursor-default ${rankCount === count ? "bg-panel text-panel-fg" : "border border-line bg-surface text-fg-muted"}`}>
                Top {count}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <ol className={`${showEditorHeader ? "mt-4 " : ""}${fullLeagueBoard ? "grid grid-flow-col grid-cols-2 grid-rows-[repeat(16,minmax(0,1fr))] gap-1.5 sm:grid-cols-4 sm:grid-rows-8" : tenTeamBoard ? "grid grid-flow-col grid-cols-2 grid-rows-5 gap-1.5" : "flex flex-col gap-1.5"}`} onDragOver={(event) => event.preventDefault()} onDrop={(event) => onDrop(event, placements.length - 1)}>
        {placements.map((id, index) => {
          if (id === null) return (
            <li
              key={`empty-${index}`}
              onDragOver={(event) => {
                if (disabled) return;
                event.preventDefault();
                setDropTargetIndex(index);
              }}
              onDrop={(event) => !disabled && onDrop(event, index)}
              className={`flex h-14 min-w-0 items-center gap-3 border border-dashed bg-surface-raised/50 px-3 text-fg-muted transition-colors ${dropTargetIndex === index && draggedId ? "border-panel ring-1 ring-panel" : "border-line"}`}
            >
              <span className="w-5 font-mono text-sm tabular-nums">{index + 1}</span>
              <span className="font-mono text-[10px] tracking-[0.08em] uppercase">Choose a team</span>
            </li>
          );
          const option = slot.options.find((item) => item.id === id)!;
          const previousRank = option.teamCode ? previousRankByTeam[option.teamCode] : undefined;
          const movement = previousRank === undefined ? "New" : previousRank - index - 1;
          return (
            <li
              key={id}
              draggable={!disabled}
              onDragStart={() => setDraggedId(id)}
              onDragEnd={() => {
                setDraggedId(null);
                setDropTargetIndex(null);
              }}
              onDragOver={(event) => {
                if (disabled) return;
                event.preventDefault();
                setDropTargetIndex(index);
              }}
              onDrop={(event) => !disabled && onDrop(event, index)}
              style={{
                ...PROMPT_TICKET_CUT_CORNERS,
                ...(option.teamCode ? { background: `linear-gradient(135deg, ${teamPrimaryColor(option.teamCode) ?? "#252722"}, #171914 72%)` } : {}),
              }}
              className={`relative grid h-14 min-w-0 grid-cols-[2.1rem_minmax(0,1fr)_2rem] overflow-hidden border text-white shadow-[0_4px_10px_rgb(0_0_0/0.28)] transition-[border-color,box-shadow] ${dropTargetIndex === index && draggedId ? "border-panel ring-1 ring-panel" : "border-white/25"} ${disabled ? "" : "cursor-grab active:cursor-grabbing"}`}
            >
              <span className="z-10 flex items-center justify-center border-r border-white/20 bg-black/45 font-slab text-2xl leading-none text-white tabular-nums">{index + 1}</span>
              <span className="relative flex min-w-0 items-center justify-center overflow-hidden">
                <OptionIcon option={option} className="h-24 w-24 shrink-0 drop-shadow-[0_5px_7px_rgb(0_0_0/0.65)]" />
              </span>
              <span className="sr-only">{option.label}</span>
              <span className="relative z-10 flex items-center justify-center border-l border-black/15 bg-[#f7f5ee]">
                <span className={`font-mono text-xs font-black tabular-nums ${movement === "New" ? "text-fg-muted" : typeof movement === "number" && movement > 0 ? "text-grade-elite" : typeof movement === "number" && movement < 0 ? "text-grade-rough" : "text-fg-muted"}`}>
                  {movement === "New" ? "—" : movement === 0 ? "—" : movement > 0 ? `+${movement}` : movement}
                </span>
              </span>
            </li>
          );
        })}
      </ol>

      {!disabled ? (
        <div className="mt-4" onDragOver={(event) => event.preventDefault()} onDrop={returnToAvailable}>
          <p className="mb-1.5 font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{draggedId && placements.includes(draggedId) ? "Drop here to remove" : "Available teams"}</p>
          <div className={`grid grid-cols-2 gap-1.5 sm:grid-cols-4 ${draggedId && placements.includes(draggedId) ? "ring-1 ring-dashed ring-panel" : ""}`}>
            {unranked.map((option) => (
              <button
                key={option.id}
                type="button"
                draggable
                onDragStart={() => setDraggedId(option.id)}
                onDragEnd={() => {
                  setDraggedId(null);
                  setDropTargetIndex(null);
                }}
                disabled={ranked.length >= rankCount}
                onClick={() => {
                  const firstEmpty = placements.indexOf(null);
                  if (firstEmpty >= 0) updatePlacements(placements.map((id, index) => index === firstEmpty ? option.id : id));
                }}
                style={{
                  ...PROMPT_TICKET_CUT_CORNERS,
                  ...(option.teamCode ? { background: `linear-gradient(135deg, ${teamPrimaryColor(option.teamCode) ?? "#252722"}, #171914 72%)` } : {}),
                }}
                aria-label={`Add ${option.label}`}
                className="group relative flex h-14 items-center justify-center overflow-hidden border border-white/20 px-3 py-0 text-white shadow-[0_4px_10px_rgb(0_0_0/0.22)] transition-transform hover:-translate-y-0.5 disabled:opacity-40"
              >
                <OptionIcon option={option} className="h-24 w-24 drop-shadow-[0_5px_7px_rgb(0_0_0/0.5)]" />
                <span className="sr-only">{option.label}</span>
                <span aria-hidden className="absolute right-2 bottom-0.5 font-mono text-xl leading-none font-black text-white/85 group-hover:text-white">+</span>
              </button>
            ))}
            {!unranked.length ? <div className="col-span-full flex h-14 items-center justify-center border border-dashed border-line bg-surface-raised/50 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">Drop a team here to remove it</div> : null}
          </div>
        </div>
      ) : null}
    </section>
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
