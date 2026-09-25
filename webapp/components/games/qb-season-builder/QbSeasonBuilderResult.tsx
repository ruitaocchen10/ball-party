"use client";

import Link from "next/link";
import { type ReactNode } from "react";

import { GuestNudge } from "@/components/games/qb-season-builder/GuestNudge";
import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { DashboardRail } from "@/components/foundation/ui-kit/DashboardRail";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import { PlayerPortrait } from "@/components/foundation/content/prompts/PlayerPortrait";
import { franchiseName } from "@/lib/foundation/content/nfl/franchises";
import {
  QUALITIES,
  SLOT_LABELS,
  type DraftPick,
  type Grade,
  type ShownSpin,
  type Slot,
} from "@/lib/games/qb-season-builder/board";
import { useSeasonReveal } from "@/lib/games/qb-season-builder/useSeasonReveal";
import {
  AWARDS,
  AWARD_LABELS,
  PLAYOFF_LABELS,
  SCORE_COMPONENT_LABELS,
  resultPath,
  type SeasonResult,
} from "@/lib/games/qb-season-builder/result";

const thousands = (value: number) => value.toLocaleString("en-US");

/** The score and a personal best are one decimal; a whole one still shows it. */
const oneDecimal = (value: number) => value.toFixed(1);

/**
 * A finished QB Season Builder season: the staged reveal the player watches
 * straight after finishing, and the same content as the read-only result page
 * anyone can open by its link.
 *
 * `staged` is the difference. The player's own reveal plays stat line, record,
 * playoffs, awards, then the score, and only then shows the breakdown and
 * recap; anyone else gets all of it at once. A
 * reveal that has been watched through, or skipped, does not play again on a
 * reload of the same run in this browser.
 *
 * Everything shown is a grade; the API never sends the values behind them.
 * `shown`, the grades of every option the player was dealt, is the player's alone:
 * a stranger's link does not carry it, so the picked-players cards there show
 * only the grade each pick was taken for. `personalBest` is the viewer's own, for this run's
 * mode; a guest is shown the nudge to make an account instead.
 *
 * Working title only — the game's name and visual design are not final.
 */
export function QbSeasonBuilderResult({
  result,
  shown,
  personalBest,
  isGuest,
  staged,
  startNewSeason,
}: {
  result: SeasonResult;
  shown: ShownSpin[] | null;
  personalBest: number | null;
  isGuest: boolean;
  staged: boolean;
  /** Supplied by the page; game UI does not reach into platform orchestration. */
  startNewSeason: (formData: FormData) => void;
}) {
  const reveal = useSeasonReveal(result.matchId, staged);

  return (
    <main className="app-page flex-1">
      <div className="grid w-full gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:items-start xl:gap-12">
        <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
          <PageHeader
            eyebrow="Solo challenge"
            title="QB Season Builder"
            description={`Grades ${result.mode}`}
          />

          <div className="mt-5 w-full max-w-[760px]">
            <div aria-live="polite" className="flex w-full flex-col gap-4">
              {reveal.shows("score") ? (
                <PlayerBuild
                  result={result}
                  shown={shown}
                  picks={result.picks}
                  showStats={reveal.shows("stat_line")}
                  showAwards={reveal.shows("awards")}
                  showScore={reveal.shows("score")}
                  showPickedPlayers={reveal.shows("awards")}
                />
              ) : null}
              {reveal.shows("record") ? <TeamSuccess result={result} showPlayoffs={reveal.shows("playoffs")} /> : null}
            </div>

            {reveal.playing ? (
              <button
                type="button"
                onClick={reveal.skip}
                className="mt-4 text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
              >
                Skip to result
              </button>
            ) : null}

            {reveal.shows("details") ? (
              <div className="mt-4 flex w-full flex-col gap-4">
                <Breakdown result={result} />
                <ResultFooter result={result} staged={staged} />
              </div>
            ) : null}
          </div>
        </div>
        <ResultRail result={result} personalBest={personalBest} isGuest={isGuest} startNewSeason={startNewSeason} />
      </div>
    </main>
  );
}

function Panel({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section aria-label={label} className="border border-line bg-surface-raised p-4">
      <h2 className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">{label}</h2>
      <div className="mt-2">{children}</div>
    </section>
  );
}

/** The QB assembled from the run — its deal history, production, score and honours. */
function PlayerBuild({
  result,
  shown,
  picks,
  showStats,
  showAwards,
  showScore,
  showPickedPlayers,
}: {
  result: SeasonResult;
  shown: ShownSpin[] | null;
  picks: DraftPick[];
  showStats: boolean;
  showAwards: boolean;
  showScore: boolean;
  showPickedPlayers: boolean;
}) {
  const { statLine } = result;
  const lines: [string, string][] = [
    ["Comp / Att", `${thousands(statLine.completions)} / ${thousands(statLine.attempts)}`],
    ["Pass yards", thousands(statLine.passYards)],
    ["Pass TDs", thousands(statLine.passTds)],
    ["Interceptions", thousands(statLine.interceptions)],
    ["Passer rating", statLine.rating.toFixed(1)],
    ["Rush yards", thousands(statLine.rushYards)],
    ["Rush TDs", thousands(statLine.rushTds)],
  ];
  return (
    <Panel label="Player build">
      {showScore ? (
        <div>
          <p className="flex items-baseline gap-2">
            <span className="font-slab text-[64px] leading-none tabular-nums">{oneDecimal(result.score)}</span>
            <span className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">out of 100</span>
          </p>
        </div>
      ) : null}
      {showStats ? (
        <dl className={`${showScore ? "mt-4 border-t border-line pt-4" : ""} grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4`}>
          {lines.map(([name, value]) => (
            <div key={name}>
              <dt className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">{name}</dt>
              <dd className="font-slab text-2xl leading-none tabular-nums">{value}</dd>
            </div>
          ))}
        </dl>
      ) : null}
      {showAwards ? <AwardIcons awards={result.awards} /> : null}
      {showPickedPlayers && picks.length > 0 ? <div className="mt-4 border-t border-line pt-4"><PickedPlayers shown={shown} picks={picks} /></div> : null}
    </Panel>
  );
}

/** Team outcomes are kept distinct from the player build that produced them. */
function TeamSuccess({ result, showPlayoffs }: { result: SeasonResult; showPlayoffs: boolean }) {
  return (
    <Panel label="Team success">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Record</p>
          <p className="mt-1 font-slab text-[40px] leading-none tabular-nums">{result.record.wins}–{result.record.losses}</p>
        </div>
        {showPlayoffs ? (
          <div className="border-t border-line pt-4 sm:border-t-0 sm:border-l sm:pt-0 sm:pl-4">
            <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Playoffs</p>
            <p className="mt-1 font-slab text-[27px] leading-none uppercase">{PLAYOFF_LABELS[result.playoffs.result]}</p>
          </div>
        ) : null}
      </div>
    </Panel>
  );
}

function AwardIcons({ awards }: { awards: SeasonResult["awards"] }) {
  const won = AWARDS.filter((award) => awards[award]);

  return (
    <div className="mt-4 border-t border-line pt-4">
      <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Awards</p>
      {won.length === 0 ? (
        <p className="mt-2 text-sm text-fg-muted">No awards this season.</p>
      ) : (
        <ul aria-label="Awards" className="mt-2 flex flex-wrap gap-2">
          {won.map((award) => (
            <li key={award} className="border border-line px-2.5 py-1 font-slab text-lg uppercase">
              {AWARD_LABELS[award]}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/**
 * Every grade the run showed for a pick: the one it was taken for, and — when
 * the player's own reveal (`shown`) is to hand — the rest of that quarterback's
 * grades and his team's Supporting Cast. A shared result page has no `shown`,
 * so it has only the taken slot.
 */
function gradesForPick(pick: DraftPick, shown: ShownSpin[] | null): Partial<Record<Slot, Grade>> {
  const grades: Partial<Record<Slot, Grade>> = {};
  if (pick.grade !== null) grades[pick.slot] = pick.grade;
  const spin = shown?.find(
    (candidate) => candidate.round === pick.round && candidate.franchiseCode === pick.franchiseCode && candidate.season === pick.season,
  );
  const quarterback = spin?.quarterbacks.find((candidate) => candidate.playerId === pick.playerId);
  if (spin && quarterback?.grades) {
    Object.assign(grades, quarterback.grades);
    if (spin.supportingCastGrade !== null) grades.supporting_cast = spin.supportingCastGrade;
  }
  return grades;
}

/** What the run took, one face per round — the team's logo for the Supporting Cast. */
function PickedPlayers({ shown, picks }: { shown: ShownSpin[] | null; picks: DraftPick[] }) {
  return (
    <div>
      <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Players picked</p>
      <ul aria-label="Players picked" className="mt-2 flex flex-wrap gap-2">
        {[...picks]
          .sort((a, b) => a.round - b.round)
          .map((pick) => (
            <li key={pick.round}>
              <PickedPlayer pick={pick} grades={gradesForPick(pick, shown)} />
            </li>
          ))}
      </ul>
    </div>
  );
}

function PickedPlayer({ pick, grades }: { pick: DraftPick; grades: Partial<Record<Slot, Grade>> }) {
  const name = pick.displayName ?? franchiseName(pick.franchiseCode);
  const slots = [...QUALITIES, "supporting_cast" as const].filter((slot) => grades[slot] !== undefined);
  return (
    <button type="button" className="group relative block rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel" aria-label={`${name}, ${SLOT_LABELS[pick.slot]}`}>
      {pick.playerId !== null ? (
        <PlayerPortrait name={name} headshotUrl={pick.headshotUrl} className="h-12 w-12 text-[12px] ring-1 ring-line" />
      ) : (
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-raised ring-1 ring-line">
          <TeamLogo code={pick.franchiseCode} className="h-8 w-8" />
        </span>
      )}
      <span className="pointer-events-none absolute top-full left-1/2 z-20 mt-2 w-56 -translate-x-1/2 bg-panel p-3 text-left text-panel-fg opacity-0 shadow-card transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
        <span className="block font-slab text-base uppercase">{name}</span>
        <span className="mt-0.5 block font-mono text-[10px] tracking-[0.1em] text-panel-muted uppercase">{pick.season} {franchiseName(pick.franchiseCode)}</span>
        {slots.length > 0 ? (
          <span className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 border-t border-panel-muted pt-2">
            {slots.map((slot) => (
              <span key={slot} className="flex items-baseline justify-between gap-2 font-mono text-[10px] tracking-[0.08em] uppercase">
                {SLOT_LABELS[slot]} <strong className={`font-slab text-base leading-none ${pick.slot === slot ? "bg-panel-fg px-1 text-panel" : ""}`}>{grades[slot]}</strong>
              </span>
            ))}
          </span>
        ) : null}
      </span>
    </button>
  );
}

function Breakdown({ result }: { result: SeasonResult }) {
  const totalWeight = result.breakdown.reduce((sum, part) => sum + part.weight, 0);
  return (
    <Panel label="Score breakdown">
      <ul className="divide-y divide-line">
        {result.breakdown.map((part) => (
          <li key={part.component} className="flex items-baseline justify-between gap-3 py-2">
            <span className="flex flex-col">
              <span className="font-mono text-[11px] font-bold tracking-[0.1em] uppercase">
                {SCORE_COMPONENT_LABELS[part.component] ?? part.component}
              </span>
              <span className="text-[13px] leading-5 text-fg-muted">
                {Math.round((100 * part.weight) / totalWeight)}% of the score · better than{" "}
                {Math.round(part.percentile * 100)}% of real seasons
              </span>
            </span>
            <span className="font-slab text-xl tabular-nums">{part.points}</span>
          </li>
        ))}
      </ul>
    </Panel>
  );
}

/** The result's persistent next-step and viewer-specific summary. */
function ResultRail({ result, personalBest, isGuest, startNewSeason }: {
  result: SeasonResult;
  personalBest: number | null;
  isGuest: boolean;
  startNewSeason: (formData: FormData) => void;
}) {
  return (
    <DashboardRail headingId="qb-result-control-heading" eyebrow="Your run" title="Next play">
      {!isGuest && personalBest !== null ? (
        <div className="mt-4 border-t border-line pt-3">
          <p className="font-mono text-[10px] font-semibold tracking-[0.13em] text-fg-muted uppercase">
            Personal best · {result.mode}
          </p>
          <p className="mt-1 font-slab text-[40px] leading-none tabular-nums">{oneDecimal(personalBest)}</p>
        </div>
      ) : null}
      {isGuest ? <div className="mt-4 border-t border-line pt-3"><GuestNudge /></div> : null}
      <div className="mt-4 flex flex-col gap-2 border-t border-line pt-3">
        <form action={startNewSeason}>
          <input type="hidden" name="game" value="qb_season_builder" />
          <input type="hidden" name="mode" value={result.mode} />
          <Button type="submit">New season</Button>
        </form>
        <ButtonLink href="/solo" variant="ghost">Back to solo games</ButtonLink>
      </div>
    </DashboardRail>
  );
}

/** Below the season: the share link that only makes sense after its reveal. */
function ResultFooter({
  result,
  staged,
}: {
  result: SeasonResult;
  staged: boolean;
}) {
  return (
    <div className="flex flex-col gap-3 border-t border-line pt-4 text-sm leading-6 text-fg-muted">
      {staged ? (
        <p>
          <Link
            href={resultPath(result.matchId)}
            className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg"
          >
            Shareable result page
          </Link>{" "}
          — anyone with the link can see this season.
        </p>
      ) : null}
    </div>
  );
}
