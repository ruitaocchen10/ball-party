"use client";

import { Check } from "lucide-react";

import { RUNNING_BACKS, TEAMS } from "./mockData";
import { nflTeamName, type NflScheduleGame } from "@/lib/nfl/schedule";
import { PlayerPortrait, ProtoTeamLogo } from "./ProtoImages";
import { Select } from "@/components/ui/Select";
import type { Option, Player, Slot, TemplateKind } from "./types";

/**
 * PROTOTYPE — throwaway. Field editors and slot builders shared by every
 * variant's composer. Shared deliberately: this is how a template's data
 * gets shaped into slots, not how the composer is laid out — each variant is
 * still free to arrange these controls however its own structure calls for.
 */

export const TEMPLATE_DEFS: { kind: TemplateKind; name: string; blurb: string }[] = [
  { kind: "picks", name: "Picks", blurb: "Pick winners for one game or a set of games." },
  { kind: "stat_leader", name: "Pick one out of these", blurb: "Choose from a pool — a season stat leader, an award." },
  { kind: "ranking", name: "Rankings", blurb: "Order a pool of teams or players." },
  { kind: "custom_multi", name: "Preseason playoff picks", blurb: "4 division winners + 3 wildcards, one prompt." },
];

export function buildGamePickSlots(game: NflScheduleGame): Slot[] {
  return [
    {
      id: `slot-${game.id}`,
      label: `${game.label} — winner`,
      shape: "pick",
      points: 10,
      options: [
        { id: game.away, label: nflTeamName(game.away), teamCode: game.away },
        { id: game.home, label: nflTeamName(game.home), teamCode: game.home },
      ],
      sourceGameId: game.id,
    },
  ];
}

export function buildStatLeaderSlots(selected: Player[]): Slot[] {
  return [
    {
      id: "slot-leader",
      label: "Leader",
      shape: "pick",
      points: 25,
      options: selected.map((p) => ({ id: p.id, label: p.name, sublabel: p.team, headshotUrl: p.headshotUrl, teamCode: p.team })),
    },
  ];
}

export function buildRankingSlots(selected: Option[], rankCount: number): Slot[] {
  return [
    {
      id: "slot-rank",
      label: `Top ${rankCount}`,
      shape: "rank",
      pickCount: rankCount,
      points: 50,
      options: selected,
    },
  ];
}

export function buildCustomMultiSlots(): Slot[] {
  const divisionSlot = (division: string, id: string, label: string): Slot => ({
    id,
    label,
    shape: "pick",
    points: 15,
    options: TEAMS.filter((t) => t.division === division).map((t) => ({ id: t.code, label: t.name, teamCode: t.code })),
  });

  return [
    divisionSlot("AFC East", "slot-afc-east", "AFC East winner"),
    divisionSlot("AFC West", "slot-afc-west", "AFC West winner"),
    divisionSlot("NFC East", "slot-nfc-east", "NFC East winner"),
    divisionSlot("NFC West", "slot-nfc-west", "NFC West winner"),
    {
      id: "slot-wildcards",
      label: "Wildcard teams (pick 3)",
      shape: "pick_set",
      pickCount: 3,
      points: 30,
      excludesSlotIds: ["slot-afc-east", "slot-afc-west", "slot-nfc-east", "slot-nfc-west"],
      options: TEAMS.map((t) => ({ id: t.code, label: t.name, sublabel: t.division, teamCode: t.code })),
    },
  ];
}

export function defaultPromptText(kind: TemplateKind, game?: NflScheduleGame, picksMode: "single" | "set" = "single"): string {
  switch (kind) {
    case "picks":
      return picksMode === "set"
        ? game ? `Week ${game.week} picks: who wins?` : "Choose a season and week to start this prompt."
        : game ? `${game.label}: who wins?` : "Choose a game to start this prompt.";
    case "game_pick":
      return game ? `${game.label}: who wins?` : "Choose a game to start this prompt.";
    case "weekly_picks":
      return game ? `Week ${game.week} picks: who wins?` : "Choose a season and week to start this prompt.";
    case "stat_leader":
      return "Who leads the NFL in rushing yards this season?";
    case "ranking":
      return "Rank the top candidates, best to worst.";
    case "custom_multi":
      return "Pick your 4 division winners, then 3 wildcard teams.";
  }
}

export function defaultCriteria(kind: TemplateKind): string {
  switch (kind) {
    case "picks":
      return "Each game resolves to whichever team wins the final score. Overtime counts.";
    case "game_pick":
      return "Resolves to whichever team wins the final score. Overtime counts.";
    case "weekly_picks":
      return "Each game resolves to whichever team wins the final score. Overtime counts.";
    case "stat_leader":
      return "Resolves to whoever leads the stat after Week 18. Ties split the points.";
    case "ranking":
      return "Rank the stated top number in order. Points are awarded for every position that matches the final order.";
    case "custom_multi":
      return "Each correct division winner is worth 15 points. Each wildcard team that makes the playoffs is worth 10 points, independent of order. A team already picked as a division winner can't also score as a wildcard.";
  }
}

export function GameSelectField({
  value,
  onChange,
  games,
}: {
  value: string;
  onChange: (gameId: string) => void;
  games: NflScheduleGame[];
}) {
  return (
    <Select
      name="game"
      ariaLabel="Upcoming game"
      value={value}
      onValueChange={onChange}
      options={games.map((g) => ({ value: g.id, label: `${g.label} · ${new Date(g.kickoff).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}` }))}
    />
  );
}

/** A generic multi-select checklist — the pool for a stat-leader, ranking, or wildcard field. */
export function CheckboxPoolField<T extends { id: string; label: string; sublabel?: string; headshotUrl?: string; teamCode?: string; teamCodes?: string[] }>({
  options,
  selectedIds,
  onToggle,
  max,
  roomyTeams = false,
}: {
  options: T[];
  selectedIds: string[];
  onToggle: (id: string) => void;
  max?: number;
  /** Weekly pick slates benefit from a more tappable, logo-forward layout. */
  roomyTeams?: boolean;
}) {
  return (
    <div className={`grid grid-cols-2 ${roomyTeams ? "gap-2 sm:grid-cols-2" : "gap-1.5 sm:grid-cols-3"}`}>
      {options.map((option) => {
        const selected = selectedIds.includes(option.id);
        const disabled = !selected && max !== undefined && selectedIds.length >= max;
        return (
          <button
            key={option.id}
            type="button"
            disabled={disabled}
            onClick={() => onToggle(option.id)}
            className={`flex items-center rounded border text-left font-mono text-[11px] uppercase transition-colors ${roomyTeams ? "gap-2.5 px-3 py-3" : "gap-1.5 px-2.5 py-2"} ${
              selected
                ? "border-panel-fg bg-panel-fg text-panel"
                : "border-[#c7bfac] bg-panel-shade text-panel-fg disabled:opacity-40"
            }`}
          >
            {option.headshotUrl ? (
              <PlayerPortrait name={option.label} headshotUrl={option.headshotUrl} className="h-5 w-5 text-[8px]" />
            ) : option.teamCodes ? (
              <span className="flex shrink-0 -space-x-1.5">
                {option.teamCodes.map((code) => <ProtoTeamLogo key={code} code={code} className={roomyTeams ? "h-7 w-7" : "h-4 w-4"} />)}
              </span>
            ) : option.teamCode ? (
              <ProtoTeamLogo code={option.teamCode} className={roomyTeams ? "h-7 w-7" : "h-4 w-4"} />
            ) : null}
            <span className="flex-1 truncate">{option.label}</span>
            {selected ? <Check className="h-3.5 w-3.5 shrink-0" strokeWidth={2.5} /> : null}
          </button>
        );
      })}
    </div>
  );
}

export function optionPoolFor(kind: TemplateKind): Option[] {
  if (kind === "stat_leader")
    return RUNNING_BACKS.map((p) => ({ id: p.id, label: p.name, sublabel: p.team, headshotUrl: p.headshotUrl, teamCode: p.team }));
  if (kind === "ranking") return TEAMS.map((t) => ({ id: t.code, label: t.name, sublabel: t.division, teamCode: t.code }));
  return [];
}
