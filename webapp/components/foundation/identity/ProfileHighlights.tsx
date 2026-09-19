"use client";

import { useState } from "react";
import * as ToggleGroup from "@radix-ui/react-toggle-group";

import { Select } from "@/components/foundation/ui-kit/Select";
import type { ProfileStatRange } from "@/lib/foundation/identity/summary";

type KnowerHighlight = {
  totalPoints: number;
  percentile: number | null;
};

type GamerHighlight = {
  gamesPlayed: number;
  wins: number;
  winRate: number;
};

export type ProfileHighlights = {
  knower: Record<ProfileStatRange, KnowerHighlight>;
  gamer: Record<ProfileStatRange, GamerHighlight>;
};

const rangeLabels: Record<ProfileStatRange, string> = {
  lifetime: "Lifetime",
  year: "Year",
  month: "Month",
  week: "Week",
};

/** One switchable profile card keeps ranking and game measures in their own contexts. */
export function ProfileHighlightsCard({ highlights }: { highlights: ProfileHighlights }) {
  const [view, setView] = useState<"knower" | "gamer">("knower");
  const [range, setRange] = useState<ProfileStatRange>("lifetime");
  const knower = highlights.knower[range];
  const gamer = highlights.gamer.lifetime;

  return (
    <section aria-label="Profile highlights" className="border-t border-line py-6">
      <div className="rounded-card border border-line bg-surface-raised p-5 shadow-well sm:p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <ToggleGroup.Root
            type="single"
            value={view}
            onValueChange={(nextView) => { if (nextView) setView(nextView as "knower" | "gamer"); }}
            aria-label="Profile stat type"
            className="inline-flex w-fit rounded-full border border-line bg-surface p-1"
          >
            <ToggleGroup.Item value="knower" className="min-h-9 rounded-full px-4 font-mono text-[10px] font-black tracking-[0.1em] text-fg-muted uppercase transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-hidden data-[state=on]:bg-hidden data-[state=on]:text-white">Ball knower</ToggleGroup.Item>
            <ToggleGroup.Item value="gamer" className="min-h-9 rounded-full px-4 font-mono text-[10px] font-black tracking-[0.1em] text-fg-muted uppercase transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-hidden data-[state=on]:bg-hidden data-[state=on]:text-white">Gamer</ToggleGroup.Item>
          </ToggleGroup.Root>
          {view === "knower" ? <div className="w-full sm:w-auto">
            <Select
              name="profile-stat-range"
              ariaLabel="Profile reporting range"
              value={range}
              onValueChange={(value) => setRange(value as ProfileStatRange)}
              options={(Object.keys(rangeLabels) as ProfileStatRange[]).map((key) => ({ value: key, label: rangeLabels[key] }))}
              variant="dark"
            />
          </div> : null}
        </div>

        {view === "knower" ? (
          <div className="mt-7 grid gap-6 sm:grid-cols-3 sm:gap-6">
            <Highlight value={knower.totalPoints.toLocaleString()} label="Total points" detail={range === "lifetime" ? "All-time prediction points" : `Last ${range === "year" ? "365 days" : range === "month" ? "30 days" : "7 days"}`} />
            <KnowerStatus percentile={highlights.knower.lifetime.percentile} />
            <KnowerStanding percentile={knower.percentile} />
          </div>
        ) : (
          <div className="mt-7 grid gap-6 sm:grid-cols-2 sm:gap-8">
            <Highlight value={gamer.gamesPlayed} label="Games played" detail="All-time multiplayer games" />
            <Highlight value={`${gamer.winRate}%`} label="Win rate" detail={`${gamer.wins} multiplayer ${gamer.wins === 1 ? "win" : "wins"}`} />
          </div>
        )}
      </div>
    </section>
  );
}

function Highlight({ value, label, detail }: { value: string | number; label: string; detail: string }) {
  return <div className="rounded-card border border-line bg-surface p-4 sm:p-5">
    <span className="block font-mono text-[10px] font-black tracking-[0.13em] text-hidden uppercase">{label}</span>
    <strong className="mt-3 block font-slab text-[42px] leading-[.9] text-fg sm:text-[48px]">{value}</strong>
    <p className="mt-1.5 text-sm leading-5 text-fg-muted">{detail}</p>
  </div>;
}

function KnowerStanding({ percentile }: { percentile: number | null }) {
  const fill = percentile === null ? 0 : Math.max(0, Math.min(100, percentile));
  const radius = 32;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - fill / 100);

  return (
    <div className="rounded-card border border-line bg-surface p-4 sm:p-5">
      <span className="block font-mono text-[10px] font-black tracking-[0.13em] text-hidden uppercase">Ball knower standing</span>
      <div className="mt-3 flex items-center gap-4">
        <div className="relative grid size-[72px] shrink-0 place-items-center" aria-label={percentile === null ? "Not ranked yet" : `${percentile}th percentile among active ball knowers`}>
          <svg viewBox="0 0 80 80" className="size-full -rotate-90" aria-hidden="true">
            <circle cx="40" cy="40" r={radius} fill="none" stroke="currentColor" strokeWidth="6" className="text-line" />
            <circle
              cx="40"
              cy="40"
              r={radius}
              fill="none"
              stroke="currentColor"
              strokeWidth="6"
              strokeLinecap="round"
              className="text-hidden transition-[stroke-dashoffset] duration-500"
              strokeDasharray={circumference}
              strokeDashoffset={dashOffset}
            />
          </svg>
          <span className="absolute text-center font-slab text-[20px] leading-none text-fg">
            {percentile === null ? "—" : `${percentile}%`}
          </span>
        </div>
        <p className="max-w-[22ch] text-sm leading-5 text-fg-muted">
          {percentile === null ? "Make a correct pick to enter the rankings" : "Among active ball knowers"}
        </p>
      </div>
    </div>
  );
}

function KnowerStatus({ percentile }: { percentile: number | null }) {
  const status = percentile === null ? "Unranked" : percentile < 20 ? "Rookie" : percentile < 40 ? "Casual" : percentile < 60 ? "Fan" : percentile < 80 ? "Ball knower" : "Ball god";

  return <div className="rounded-card border border-line bg-surface p-4 sm:p-5">
    <span className="block font-mono text-[10px] font-black tracking-[0.13em] text-hidden uppercase">Ball knower status</span>
    <strong className="mt-3 block font-slab text-[32px] leading-[.9] text-fg uppercase sm:text-[38px]">{status}</strong>
    <p className="mt-2 text-sm leading-5 text-fg-muted">{percentile === null ? "Your lifetime score will set your status" : `Lifetime · ${ordinal(percentile)} percentile`}</p>
  </div>;
}

function ordinal(value: number) {
  const remainder = value % 100;
  if (remainder >= 11 && remainder <= 13) return `${value}th`;
  return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`;
}
