"use client";

import { Check, X } from "lucide-react";
import { useState } from "react";

import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import { PromptTeamLogo } from "./PromptTeamLogo";
import { PROMPT_TICKET_CUT_CORNERS, PromptTicket } from "./PromptTicket";
import { isSlotGraded, isSlotNoContest } from "@/lib/foundation/content/prompts/logic";
import type { Option, Slot } from "@/lib/foundation/content/prompts/types";

type Props = {
  slot: Slot;
  mode: "picker" | "revealed";
  response?: string[];
  onChange?: (response: string[]) => void;
  testId?: string;
};

/** One matchup module for choices and revealed calls. A Game Picks slot (winner + margin) gets the four-choice layout. */
export function MatchupPicker(props: Props) {
  return props.slot.options.some((option) => option.margin) ? <MarginPicker {...props} /> : <WinnerPicker {...props} />;
}

function WinnerPicker({ slot, mode, response = [], onChange, testId }: Props) {
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [away, home] = slot.options;
  if (!away || !home) return null;
  const selectedId = response[0] ?? null;
  const activeId = mode === "picker" ? hoveredId ?? selectedId : selectedId;
  // A pick is only marked once this slot's own answer is known — on a weekly
  // post the Thursday game can be graded while Monday's is still pending.
  const graded = mode === "revealed" && isSlotGraded(slot);
  const correct = graded && selectedId === slot.correct?.[0];
  const noContest = mode === "revealed" && isSlotNoContest(slot);
  const sideProps = (option: Option) => mode !== "picker" ? {} : {
    role: "button" as const,
    tabIndex: 0,
    "aria-pressed": selectedId === option.id,
    onClick: () => onChange?.([option.id]),
    onKeyDown: (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onChange?.([option.id]); }
    },
    onMouseEnter: () => setHoveredId(option.id), onMouseLeave: () => setHoveredId(null),
    onFocus: () => setHoveredId(option.id), onBlur: () => setHoveredId(null),
  };

  return (
    <PromptTicket data-testid={testId} aria-label={slot.label} className="min-w-0 ring-1 ring-line ring-inset">
      <div className="relative grid grid-cols-2 divide-x divide-line">
        <CompactSide option={away} selected={selectedId === away.id} hasSelection={selectedId !== null} active={activeId === away.id} interactive={mode === "picker"} revealed={graded} correct={correct} sideProps={sideProps(away)} />
        <CompactSide option={home} selected={selectedId === home.id} hasSelection={selectedId !== null} active={activeId === home.id} interactive={mode === "picker"} revealed={graded} correct={correct} sideProps={sideProps(home)} />
        <div aria-hidden className="pointer-events-none absolute inset-y-0 left-1/2 z-10 flex -translate-x-1/2 items-center justify-center"><span className="absolute inset-y-2 left-1/2 w-px bg-line sm:inset-y-3" /><span className="relative flex h-6 w-6 items-center justify-center rounded-full border border-line bg-surface font-mono text-[10px] font-bold text-fg-muted sm:h-8 sm:w-8 sm:text-xs">@</span></div>
      </div>
      {noContest ? <p className="border-t border-line/70 py-1 text-center type-label-xs text-fg-muted">No contest — game tied</p> : <div aria-hidden className="mx-2 h-2 border-t border-line/70 sm:mx-3" />}
    </PromptTicket>
  );
}

function surface(option: Option, active: boolean) {
  const color = option.teamCode ? teamPrimaryColor(option.teamCode) : null;
  return active && color ? { background: `linear-gradient(135deg, ${color}, #111311)`, color: "#fffdf7" } : undefined;
}

function CompactSide({ option, selected, hasSelection, active, interactive, revealed, correct, sideProps }: { option: Option; selected: boolean; hasSelection: boolean; active: boolean; interactive: boolean; revealed: boolean; correct: boolean; sideProps: Record<string, unknown> }) {
  const grade = selected && revealed ? correct ? "ring-1 ring-inset ring-grade-elite" : "ring-1 ring-inset ring-grade-rough" : "";
  return <div {...sideProps} style={{ ...surface(option, active), clipPath: "inset(0 -10rem 0 -10rem)" }} className={`relative flex h-12 min-w-0 items-center justify-center px-1 py-2 transition-all duration-150 sm:h-20 sm:px-2 sm:py-3 ${active ? "" : selected ? "text-fg" : "bg-surface/85 text-fg-muted"} ${grade} ${interactive ? "cursor-pointer hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-fg" : ""}`}><OptionMark option={option} className={`h-28 w-28 sm:h-40 sm:w-40${hasSelection && !selected ? " grayscale opacity-40" : ""}`} /><span className="sr-only">{option.label}</span>{revealed && selected ? correct ? <Check aria-label="Correct" className="absolute top-1.5 right-1.5 h-3.5 w-3.5 text-grade-elite sm:top-2 sm:right-2 sm:h-4 sm:w-4" strokeWidth={3} /> : <X aria-label="Incorrect" className="absolute top-1.5 right-1.5 h-3.5 w-3.5 text-grade-rough sm:top-2 sm:right-2 sm:h-4 sm:w-4" strokeWidth={3} /> : null}</div>;
}

function OptionMark({ option, className }: { option: Option; className: string }) {
  if (option.teamCodes) return <span className="flex -space-x-1.5">{option.teamCodes.map((code) => <PromptTeamLogo key={code} code={code} className={className} />)}</span>;
  return option.teamCode ? <PromptTeamLogo code={option.teamCode} className={className} /> : null;
}

export function formatGameTime(kickoff: string | undefined) {
  if (!kickoff || Number.isNaN(new Date(kickoff).getTime())) return "Game time TBD";
  return new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", weekday: "short", hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(new Date(kickoff));
}

/** Game Picks: the four choices — each team's "by <7" and "by 7+" — in a column per team. */
function MarginPicker({ slot, mode, response = [], onChange, testId }: Props) {
  const selectedId = response[0] ?? null;
  const graded = mode === "revealed" && isSlotGraded(slot);
  const [awayShort, awayLong, homeShort, homeLong] = slot.options;
  if (!awayShort || !awayLong || !homeShort || !homeLong) return null;
  const picking = mode === "picker";
  return (
    <section data-testid={testId} aria-label={slot.label}>
      {picking ? <p className="mt-4 type-label text-fg-muted">Pick the winner and margin</p> : null}
      <div role={picking ? "radiogroup" : undefined} aria-label="Winner and margin" className={`grid grid-cols-2 gap-3 ${picking ? "mt-2" : ""}`}>
        {[awayShort, homeShort, awayLong, homeLong].map((option) => {
          const selected = selectedId === option.id;
          const isCorrect = graded && selected && option.id === slot.correct?.[0];
          const isWrong = graded && selected && !isCorrect;
          const choiceProps = mode !== "picker" ? {} : {
            role: "radio" as const,
            "aria-checked": selected,
            tabIndex: 0,
            onClick: () => onChange?.([option.id]),
            onKeyDown: (event: React.KeyboardEvent<HTMLDivElement>) => {
              if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onChange?.([option.id]); }
            },
          };
          return (
            <div
              key={option.id}
              {...choiceProps}
              data-testid={`margin-choice-${option.id}`}
              style={{ ...PROMPT_TICKET_CUT_CORNERS, ...(selected ? surface(option, true) : {}) }}
              className={`relative flex min-h-20 min-w-0 items-center gap-3 px-3 py-3 text-left ring-2 ring-inset transition-all duration-150 sm:min-h-24 sm:px-4 ${isCorrect ? "ring-grade-elite" : isWrong ? "ring-grade-rough" : selected ? "ring-fg/70" : "ring-line"} ${picking ? "cursor-pointer hover:ring-fg/50 hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-fg" : ""} ${selected ? "text-[#fffdf7]" : picking ? "bg-surface-raised text-fg" : "bg-surface-raised text-fg-muted"}`}
            >
              <OptionMark option={option} className={`h-10 w-10 shrink-0 sm:h-14 sm:w-14${selectedId && !selected ? " grayscale opacity-40" : ""}`} />
              <span className="min-w-0"><span className={`block truncate font-slab leading-tight uppercase text-lg sm:text-xl`}>{option.label}</span>{option.sublabel ? <span className={`block truncate type-label opacity-70`}>{option.sublabel}</span> : null}</span>
              {isCorrect ? <Check aria-label="Correct" className="absolute top-2 right-3 h-4 w-4 text-grade-elite" strokeWidth={3} /> : isWrong ? <X aria-label="Incorrect" className="absolute top-2 right-3 h-4 w-4 text-grade-rough" strokeWidth={3} /> : picking && selected ? <Check aria-hidden className="absolute top-2 right-3 h-4 w-4 text-white drop-shadow" strokeWidth={3} /> : null}
            </div>
          );
        })}
      </div>
    </section>
  );
}
