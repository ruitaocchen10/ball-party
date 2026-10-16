"use client";

import { useState } from "react";
import * as ToggleGroup from "@radix-ui/react-toggle-group";

import { Select } from "@/components/foundation/ui-kit/Select";
import type { ProfileStatRange } from "@/lib/foundation/identity/summary";

type KnowerHighlight = {
  totalPoints: number;
  percentile: number | null;
  /** The server's split of totalPoints; likes are net of dislikes, so they can be negative. */
  pickPoints: number;
  likePoints: number;
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
            <ToggleGroup.Item value="knower" className="min-h-9 rounded-full px-4 type-label font-black text-fg-muted transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-hidden data-[state=on]:bg-hidden data-[state=on]:text-white">Ball knower</ToggleGroup.Item>
            <ToggleGroup.Item value="gamer" className="min-h-9 rounded-full px-4 type-label font-black text-fg-muted transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-hidden data-[state=on]:bg-hidden data-[state=on]:text-white">Gamer</ToggleGroup.Item>
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
          <div className="mt-7 grid grid-cols-2 gap-3 sm:gap-6">
            <KnowerPoints knower={knower} />
            <KnowerStatus percentile={highlights.knower.lifetime.percentile} />
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
  return <div className="rounded-card border border-line bg-surface p-4 sm:p-5 flex min-h-[190px] flex-col justify-between">
    <span className="block type-label font-black text-hidden">{label}</span>
    <strong className="mt-3 block font-slab text-[42px] leading-[.9] text-fg sm:text-[48px]">{value}</strong>
    <p className="mt-1.5 text-sm leading-5 text-fg-muted">{detail}</p>
  </div>;
}

const GAUGE_RADIUS = 78;
const GAUGE_ARC = `M ${100 - GAUGE_RADIUS} 100 A ${GAUGE_RADIUS} ${GAUGE_RADIUS} 0 0 1 ${100 + GAUGE_RADIUS} 100`;

/** The bar fills to the player's percentile for the range; picks and likes split that fill by their share of the points. */
function KnowerPoints({ knower }: { knower: KnowerHighlight }) {
  const fill = knower.percentile === null ? 0 : Math.max(0, Math.min(100, knower.percentile));
  const picks = Math.max(0, knower.pickPoints);
  const likes = Math.max(0, knower.likePoints);
  const likeShare = picks + likes > 0 ? likes / (picks + likes) : 0;
  const pickLength = fill * (1 - likeShare);
  const likeLength = fill * likeShare;

  return <div className="rounded-card border border-line bg-surface p-4 sm:p-5 flex min-h-[190px] flex-col justify-between">
    <span className="block type-label font-black text-hidden">Ball knower points</span>
    <div
      className="relative mx-auto mt-3 w-full max-w-[220px]"
      role="img"
      aria-label={knower.percentile === null ? `${knower.totalPoints} points, not ranked yet` : `${knower.totalPoints} points, ${ordinal(knower.percentile)} percentile`}
    >
      <svg viewBox="0 0 200 120" className="block w-full" aria-hidden="true">
        <path d={GAUGE_ARC} pathLength={100} fill="none" strokeWidth="36" strokeLinecap="round" className="stroke-line" />
        {/* Likes run the full fill and the picks draw over their share, so both ends stay round without a seam. */}
        {likeLength > 0 ? <path d={GAUGE_ARC} pathLength={100} fill="none" strokeWidth="36" strokeLinecap="round" strokeDasharray={`${fill} 100`} className="stroke-ball" /> : null}
        {pickLength > 0 ? <path d={GAUGE_ARC} pathLength={100} fill="none" strokeWidth="36" strokeLinecap="round" strokeDasharray={`${pickLength} 100`} className="stroke-fg" /> : null}
      </svg>
      <strong className="absolute inset-x-0 bottom-0 text-center font-slab text-[32px] leading-none text-fg sm:text-[40px]">{knower.totalPoints.toLocaleString()}</strong>
    </div>
    <ul className="mt-3 flex flex-wrap justify-center gap-x-4 gap-y-1 text-sm text-fg-muted">
      <li className="flex items-center gap-1.5"><span className="size-2.5 rounded-full bg-fg" aria-hidden="true" />Picks</li>
      <li className="flex items-center gap-1.5"><span className="size-2.5 rounded-full bg-ball" aria-hidden="true" />Likes</li>
    </ul>
  </div>;
}

function KnowerStatus({ percentile }: { percentile: number | null }) {
  const status = percentile === null ? "Unranked" : percentile < 20 ? "Rookie" : percentile < 40 ? "Casual" : percentile < 60 ? "Fan" : percentile < 80 ? "Ball knower" : "Ball god";

  return <div className="rounded-card border border-line bg-surface p-4 sm:p-5 flex min-h-[190px] flex-col justify-between">
    <span className="block type-label font-black text-hidden">Status</span>
    <strong className="mt-3 block font-slab text-[24px] leading-[.9] text-fg uppercase sm:text-[38px]">{status}</strong>
    <p className="mt-2 text-sm leading-5 text-fg-muted">{percentile === null ? "Not ranked yet" : `${ordinal(percentile)} percentile`}</p>
  </div>;
}

function ordinal(value: number) {
  const remainder = value % 100;
  if (remainder >= 11 && remainder <= 13) return `${value}th`;
  return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`;
}
