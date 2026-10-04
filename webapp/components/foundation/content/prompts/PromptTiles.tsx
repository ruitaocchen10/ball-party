"use client";

import { Check } from "lucide-react";

import { PromptTeamLogo } from "./PromptTeamLogo";
import { PROMPT_TICKET_CUT_CORNERS, PromptTicket } from "./PromptTicket";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";

export const teamSurface = (code: string) => ({ background: `linear-gradient(135deg, ${teamPrimaryColor(code) ?? "#252722"}, #171914 72%)` });

/** A matchup as the compact ticket the winner picker uses, but tagging the whole game rather than a side. */
export function MatchupTile({ away, home, label, pressed, dimmed, onClick }: { away: string; home: string; label: string; pressed: boolean; dimmed: boolean; onClick: () => void }) {
  const half = (code: string) => (
    <span
      style={pressed ? { ...teamSurface(code), color: "#fffdf7" } : undefined}
      className={`flex h-12 min-w-0 items-center justify-center overflow-hidden px-1 py-2 transition-all duration-150 sm:h-20 sm:px-2 sm:py-3 ${pressed ? "" : "bg-surface/85"}`}
    >
      <PromptTeamLogo code={code} className={`h-28 w-28 shrink-0 sm:h-40 sm:w-40${dimmed ? " grayscale opacity-40" : ""}`} />
    </span>
  );
  return (
    <button
      type="button"
      aria-pressed={pressed}
      aria-label={label}
      onClick={onClick}
      className="group block min-w-0 cursor-pointer text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
    >
      <PromptTicket className={`min-w-0 ring-1 ring-inset ${pressed ? "ring-fg/70" : "ring-line group-hover:ring-fg/40"}`}>
        <span className="relative grid grid-cols-2 divide-x divide-line">
          {half(away)}
          {half(home)}
          <span aria-hidden className="pointer-events-none absolute inset-y-0 left-1/2 z-10 flex -translate-x-1/2 items-center justify-center">
            <span className="relative flex h-6 w-6 items-center justify-center rounded-full border border-line bg-surface font-mono text-[10px] font-bold text-fg-muted sm:h-8 sm:w-8 sm:text-xs">@</span>
          </span>
          {pressed ? <Check aria-hidden className="absolute top-1.5 right-1.5 z-20 h-4 w-4 text-white drop-shadow" strokeWidth={3} /> : null}
        </span>
        <span aria-hidden className="mx-2 block h-2 border-t border-line/70 sm:mx-3" />
      </PromptTicket>
    </button>
  );
}

/** A team as the power-rankings "Available teams" tile: its colors behind an oversized logo. */
export function TeamTile({ code, name, pressed, dimmed, onClick }: { code: string; name: string; pressed: boolean; dimmed: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={pressed}
      aria-label={name}
      onClick={onClick}
      style={{ ...PROMPT_TICKET_CUT_CORNERS, ...teamSurface(code) }}
      className={`relative flex h-14 items-center justify-center overflow-hidden border px-3 py-0 text-white shadow-[0_4px_10px_rgb(0_0_0/0.22)] transition-[transform,opacity] hover:-translate-y-0.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel ${pressed ? "border-white ring-2 ring-white" : "border-white/20"} ${dimmed ? "opacity-45" : ""} cursor-pointer`}
    >
      <PromptTeamLogo code={code} className="h-24 w-24 shrink-0 drop-shadow-[0_5px_7px_rgb(0_0_0/0.5)]" />
      {pressed ? <Check aria-hidden className="absolute top-1.5 right-2 h-4 w-4 text-white drop-shadow" strokeWidth={3} /> : null}
    </button>
  );
}
