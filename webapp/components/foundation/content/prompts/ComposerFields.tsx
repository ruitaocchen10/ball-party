"use client";

import { Check } from "lucide-react";

import { RUNNING_BACKS, TEAMS } from "@/lib/foundation/content/prompts/staticOptionPools";
import { nflTeamName, type NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { PlayerPortrait } from "./PlayerPortrait";
import { PromptTeamLogo } from "./PromptTeamLogo";
import { Select } from "@/components/foundation/ui-kit/Select";
import { COVER_OPTION_LIMIT } from "@/lib/foundation/content/prompts/logic";
import type { Option, OptionMargin, Player, Slot, TemplateKind } from "@/lib/foundation/content/prompts/types";

/**
 * Field editors and slot builders shared by every variant's composer.
 * Shared deliberately: this is how a template's data
 * gets shaped into slots, not how the composer is laid out — each variant is
 * still free to arrange these controls however its own structure calls for.
 */

/** Kinds the composer can author. `picks` and `custom_multi` exist on old posts but can no longer be created. */
export type ComposerKind = Exclude<TemplateKind, "picks" | "custom_multi">;

/** Kinds that are always opinion prompts — the composer hides the toggle and never grades them. */
export const OPINION_ONLY_KINDS: ComposerKind[] = ["power_rankings", "weekly_awards", "bold_predictions"];

export const TEMPLATE_DEFS: { kind: ComposerKind; name: string; blurb: string }[] = [
  { kind: "game_pick", name: "Game Picks", blurb: "Pick the winner of one game and the margin." },
  { kind: "weekly_picks", name: "Weekly Picks", blurb: "Pick winners for a week's slate of games." },
  { kind: "weekly_awards", name: "Weekly Awards", blurb: "Six awards for the week: best and worst teams, best game, and three players." },
  { kind: "stat_leader", name: "Pick one out of these", blurb: "Choose from a pool — a season stat leader, an award." },
  { kind: "ranking", name: "Rankings", blurb: "Order a pool of teams or players." },
  { kind: "power_rankings", name: "Power rankings", blurb: "Let each person rank their NFL top 5, 10, or 32." },
  { kind: "bold_predictions", name: "Bold Predictions", blurb: "Write up to five tagged calls for the week and lock them in as one response to see everyone else's." },
];

/** How long before a week's first kickoff a Bold Predictions post locks by default. */
const BOLD_LOCK_LEAD_MS = 3600_000;

/**
 * Where a Bold Predictions post's lock time may fall. A post is about the week
 * whose first kickoff follows its lock (0171), so it must lock after the
 * previous week's last kickoff and no later than this week's last one (a post
 * that opens Saturday and locks at the first Sunday kickoff is fine; only games
 * from the lock on can be tagged, 0217). Outside that, matchup tags would be
 * offered for, and validated against, the wrong week.
 */
export function boldLockBounds(games: NflScheduleGame[], season: number, week: number): { firstKickoff: Date | null; lastKickoff: Date | null; previousEnd: Date | null } {
  const kickoffs = (wanted: number) => games.filter((game) => game.season === season && game.week === wanted).map((game) => new Date(game.kickoff).getTime());
  const thisWeek = kickoffs(week);
  const lastWeek = kickoffs(week - 1);
  return {
    firstKickoff: thisWeek.length ? new Date(Math.min(...thisWeek)) : null,
    lastKickoff: thisWeek.length ? new Date(Math.max(...thisWeek)) : null,
    previousEnd: lastWeek.length ? new Date(Math.max(...lastWeek)) : null,
  };
}

/** The suggested lock for a week's Bold Predictions: an hour before its first kickoff. */
export function defaultBoldLockAt(games: NflScheduleGame[], season: number, week: number): Date | null {
  const { firstKickoff } = boldLockBounds(games, season, week);
  return firstKickoff ? new Date(firstKickoff.getTime() - BOLD_LOCK_LEAD_MS) : null;
}

/** Default value of a Game Picks post; a Weekly Picks game stays at 10. */
export const GAME_PICK_POINTS = 20;

/** One game, one pick: the winner and whether they win by under 7 or by 7+ (exactly 7 is 7+). */
export function buildGamePickSlots(game: NflScheduleGame): Slot[] {
  const option = (code: string, margin: OptionMargin): Option => ({
    id: `${code}-${margin}`,
    label: `${nflTeamName(code)} by ${margin === "under_7" ? "<7" : "7+"}`,
    sublabel: margin === "under_7" ? "Wins by 1–6" : "Wins by 7 or more",
    teamCode: code,
    margin,
  });
  return [
    {
      id: `slot-${game.id}`,
      label: `${game.label} — winner and margin`,
      shape: "pick",
      points: GAME_PICK_POINTS,
      options: [option(game.away, "under_7"), option(game.away, "7_plus"), option(game.home, "under_7"), option(game.home, "7_plus")],
      sourceGameId: game.id,
    },
  ];
}

/** One winner-only slot per game of a Weekly Picks slate. */
export function buildWeeklyPickSlots(game: NflScheduleGame): Slot[] {
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

/**
 * `coverIds` are the players the admin chose for the prompt's art, in
 * placement order. Only a pool bigger than the art needs them — a smaller one
 * is shown whole.
 */
export function buildStatLeaderSlots(selected: Player[], coverIds: string[] = []): Slot[] {
  const choosesCover = selected.length > COVER_OPTION_LIMIT;
  return [
    {
      id: "slot-leader",
      label: "Leader",
      shape: "pick",
      points: 25,
      options: selected.map((p) => ({
        id: p.id,
        label: p.name,
        sublabel: p.team,
        headshotUrl: p.headshotUrl,
        teamCode: p.team,
        ...(choosesCover && coverIds.includes(p.id) ? { coverPosition: coverIds.indexOf(p.id) + 1 } : {}),
      })),
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

export const AWARD_LABELS = {
  winner: "Biggest winner",
  loser: "Biggest loser",
  game: "Best game",
  offense: "Offensive player of the week",
  defense: "Defensive player of the week",
  lvp: "LVP (least valuable player)",
} as const;

/**
 * Weekly Awards: always the same six required slots, in this order. The team
 * slots offer the whole league and the game slot that week's schedule; the
 * three player slots carry no options — respondents search the directory, and
 * an option is created for a player the first time someone picks them.
 */
export function buildWeeklyAwardsSlots(games: NflScheduleGame[]): Slot[] {
  const teams = (): Option[] => TEAMS.map((team) => ({ id: team.code, label: team.name, sublabel: team.division, teamCode: team.code }));
  const slot = (id: string, label: string, options: Option[], playerSearch = false): Slot => ({
    id: `slot-${id}`, label, shape: "pick", points: 1, options, ...(playerSearch ? { playerSearch: true } : {}),
  });
  return [
    slot("winner", AWARD_LABELS.winner, teams()),
    slot("loser", AWARD_LABELS.loser, teams()),
    slot("game", AWARD_LABELS.game, games.map((game) => ({ id: game.id, label: game.label, sublabel: `${game.away} @ ${game.home}`, teamCodes: [game.away, game.home] }))),
    slot("offense", AWARD_LABELS.offense, [], true),
    slot("defense", AWARD_LABELS.defense, [], true),
    slot("lvp", AWARD_LABELS.lvp, [], true),
  ];
}

/** A Power Rankings post always publishes the full league; the respondent chooses their own top-N. */
export function buildPowerRankingSlots(): Slot[] {
  return [{
    id: "slot-power-rank",
    label: "NFL Power Rankings",
    shape: "rank",
    pickCount: 32,
    points: 1,
    options: TEAMS.map((team) => ({ id: team.code, label: team.name, sublabel: team.division, teamCode: team.code })),
  }];
}

const OPINION_AWARDS_CRITERIA = "Opinion only — there are no right answers and no points. Pick all six, then see how everyone else voted.";

export function defaultPromptText(kind: ComposerKind, game?: NflScheduleGame): string {
  switch (kind) {
    case "game_pick":
      return game ? `${game.label.replace(" @ ", " vs. ")}: Who wins?` : "Choose a game to start this prompt.";
    case "weekly_picks":
      return game ? `NFL Week ${game.week} Picks` : "Choose a season and week to start this prompt.";
    case "stat_leader":
      return "Who leads the NFL in rushing yards this season?";
    case "ranking":
      return "Rank the top candidates, best to worst.";
    case "weekly_awards":
      return game ? `NFL Week ${game.week} Awards` : "Choose a season and week to start this prompt.";
    case "power_rankings":
      return game ? `Pre Week ${game.week} Power Rankings` : "Choose a season and week to start this prompt.";
    case "bold_predictions":
      return game ? `NFL Week ${game.week} Bold Predictions` : "Choose a season and week to start this prompt.";
  }
}

export function defaultCriteria(kind: ComposerKind): string {
  switch (kind) {
    case "game_pick":
      return "Pick the winner and the margin: under 7 points, or 7 or more (exactly 7 counts as 7+). All or nothing. Overtime counts. A tie voids the prompt.";
    case "weekly_picks":
      return "Each game resolves to whichever team wins the final score. Overtime counts.";
    case "stat_leader":
      return "Resolves to whoever leads the stat after Week 18. Ties split the points.";
    case "ranking":
      return "Rank the stated top number in order. Points are awarded for every position that matches the final order.";
    case "weekly_awards":
      return OPINION_AWARDS_CRITERIA;
    case "power_rankings":
      return "Rank your NFL top 5, top 10, or all 32 teams. Your movement is compared with your most recent Power Rankings.";
    case "bold_predictions":
      return "Opinion only — there's no correct answer, so no points are awarded. Make up to five predictions, each tagged to a matchup, team or player. Lock them in as one response to see everyone else's — it can't be changed after.";
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
            className={`flex items-center rounded-chip border text-left font-mono text-[11px] uppercase transition-colors ${roomyTeams ? "gap-2.5 px-3 py-3" : "gap-1.5 px-2.5 py-2"} ${
              selected
                ? "border-panel-fg bg-panel-fg text-panel"
                : "border-panel-line bg-panel-shade text-panel-fg disabled:opacity-40"
            }`}
          >
            {option.headshotUrl ? (
              <PlayerPortrait name={option.label} headshotUrl={option.headshotUrl} className="h-5 w-5 text-[8px]" />
            ) : option.teamCodes ? (
              <span className="flex shrink-0 -space-x-1.5">
                {option.teamCodes.map((code) => <PromptTeamLogo key={code} code={code} className={roomyTeams ? "h-7 w-7" : "h-4 w-4"} />)}
              </span>
            ) : option.teamCode ? (
              <PromptTeamLogo code={option.teamCode} className={roomyTeams ? "h-7 w-7" : "h-4 w-4"} />
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
