"use client";

import Link from "next/link";
import { type ReactNode } from "react";

import { GuestNudge } from "@/components/games/qb-season-builder/GuestNudge";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { franchiseName } from "@/lib/foundation/content/nfl/franchises";
import {
  QUALITIES,
  SLOT_LABELS,
  type DraftPick,
  type Quarterback,
  type ShownSpin,
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
 * playoffs, awards, then the score, and only then shows the breakdown, the
 * recap and the closest real season; anyone else gets all of it at once. A
 * reveal that has been watched through, or skipped, does not play again on a
 * reload of the same run in this browser.
 *
 * Everything shown is the API's blended values. `shown`, the values of every
 * option the player was dealt, is the player's alone and only meaningful for a
 * hidden run: a visible run had them on screen all along, and a stranger's
 * link does not carry them. `personalBest` is the viewer's own, for this run's
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
}: {
  result: SeasonResult;
  shown: ShownSpin[] | null;
  personalBest: number | null;
  isGuest: boolean;
  staged: boolean;
}) {
  const reveal = useSeasonReveal(result.matchId, staged);

  return (
    <main className="app-page flex-1">
      <div className="mx-auto w-full max-w-[1080px]">
        <PageHeader
          eyebrow="Solo challenge"
          title="QB Season Builder"
          description={`Ratings ${result.mode}`}
        />

        <div aria-live="polite" className="mt-5 flex w-full max-w-[760px] flex-col gap-4">
          {reveal.shows("stat_line") ? <StatLine result={result} /> : null}
          {reveal.shows("record") ? <Record result={result} /> : null}
          {reveal.shows("playoffs") ? <Playoffs result={result} /> : null}
          {reveal.shows("awards") ? <Awards result={result} /> : null}
          {reveal.shows("score") ? <Score result={result} /> : null}
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
          <div className="mt-4 flex w-full max-w-[760px] flex-col gap-4">
            <Breakdown result={result} />
            <Recap picks={result.picks} />
            <Closest result={result} />
            {result.mode === "hidden" && shown ? <EverythingSeen shown={shown} picks={result.picks} /> : null}
            <ResultFooter result={result} personalBest={personalBest} isGuest={isGuest} staged={staged} />
          </div>
        ) : null}
      </div>
    </main>
  );
}

function Panel({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section aria-label={label} className="border border-line bg-surface-raised p-4">
      <h2 className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">{label}</h2>
      {children}
    </section>
  );
}

function StatLine({ result }: { result: SeasonResult }) {
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
    <Panel label="Stat line">
      <dl className="mt-2 grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4">
        {lines.map(([name, value]) => (
          <div key={name}>
            <dt className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">{name}</dt>
            <dd className="font-slab text-2xl leading-none tabular-nums">{value}</dd>
          </div>
        ))}
      </dl>
    </Panel>
  );
}

function Record({ result }: { result: SeasonResult }) {
  return (
    <Panel label="Record">
      <p className="mt-2 font-slab text-[40px] leading-none tabular-nums">
        {result.record.wins}–{result.record.losses}
      </p>
    </Panel>
  );
}

function Playoffs({ result }: { result: SeasonResult }) {
  return (
    <Panel label="Playoffs">
      <p className="mt-2 font-slab text-[27px] leading-none uppercase">{PLAYOFF_LABELS[result.playoffs.result]}</p>
    </Panel>
  );
}

function Awards({ result }: { result: SeasonResult }) {
  const won = AWARDS.filter((award) => result.awards[award]);
  return (
    <Panel label="Awards">
      {won.length === 0 ? (
        <p className="mt-2 text-sm text-fg-muted">No awards this season.</p>
      ) : (
        <ul className="mt-2 flex flex-wrap gap-2">
          {won.map((award) => (
            <li key={award} className="border border-line px-2.5 py-1 font-slab text-lg uppercase">
              {AWARD_LABELS[award]}
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

function Score({ result }: { result: SeasonResult }) {
  return (
    <Panel label="Score">
      <p className="mt-2 flex items-baseline gap-2">
        <span className="font-slab text-[64px] leading-none tabular-nums">{oneDecimal(result.score)}</span>
        <span className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">out of 100</span>
      </p>
    </Panel>
  );
}

function Breakdown({ result }: { result: SeasonResult }) {
  const totalWeight = result.breakdown.reduce((sum, part) => sum + part.weight, 0);
  return (
    <Panel label="Score breakdown">
      <ul className="mt-2 divide-y divide-line">
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

/** Which real season a pick came from: "2013 Denver Broncos". */
const seasonOf = (pick: { season: number; franchiseCode: string }) =>
  `${pick.season} ${franchiseName(pick.franchiseCode)}`;

function Recap({ picks }: { picks: DraftPick[] }) {
  return (
    <Panel label="Your six picks">
      <ol aria-label="Your six picks" className="mt-2 divide-y divide-line">
        {picks.map((pick) => (
          <li key={pick.slot} className="flex items-baseline justify-between gap-3 py-2">
            <span className="flex flex-col">
              <span className="font-mono text-[11px] font-bold tracking-[0.1em] uppercase">{SLOT_LABELS[pick.slot]}</span>
              <span className="text-[13px] leading-5 text-fg-muted">
                {pick.displayName ? `${pick.displayName} · ${seasonOf(pick)}` : seasonOf(pick)}
              </span>
            </span>
            {pick.value !== null ? <span className="font-slab text-xl tabular-nums">{pick.value}</span> : null}
          </li>
        ))}
      </ol>
    </Panel>
  );
}

function Closest({ result }: { result: SeasonResult }) {
  const real = result.closestSeason;
  return (
    <Panel label="Closest real season">
      <p className="mt-2 text-sm leading-6">
        <span className="font-slab text-xl uppercase">{real.displayName}</span>,{" "}
        <span>{seasonOf(real)}</span>
        <span className="text-fg-muted">
          {" "}— {thousands(real.passYards)} yards, {real.passTds} TD, {real.interceptions} INT, {real.wins}–{real.losses}
        </span>
      </p>
    </Panel>
  );
}

/**
 * A hidden run's reveal: every spin the player was dealt and what each option
 * was worth, the ones passed on included, so they can see how good their reads
 * were. A spin thrown away by the respin is here too — they saw it.
 */
function EverythingSeen({ shown, picks }: { shown: ShownSpin[]; picks: DraftPick[] }) {
  // The attempt a round ended on. Anything before it is a spin the respin threw
  // away, and only the kept one can hold that round's pick — which is what
  // decides where "Taken" goes, rather than the team-season, since the same one
  // may be spun again in a later round.
  const keptAttempt = new Map<number, number>();
  for (const spin of shown) {
    keptAttempt.set(spin.round, Math.max(keptAttempt.get(spin.round) ?? 0, spin.attempt));
  }
  const takenFrom = (spin: ShownSpin) =>
    spin.attempt === keptAttempt.get(spin.round)
      ? picks.find((pick) => pick.round === spin.round)
      : undefined;

  return (
    <Panel label="Every option you saw">
      <ul className="mt-2 flex flex-col gap-4">
        {shown.map((spin) => {
          const taken = takenFrom(spin);
          return (
            <li key={`${spin.round}-${spin.attempt}`}>
              <p className="flex flex-wrap items-baseline gap-2">
                <span className="font-slab text-lg uppercase">{`Round ${spin.round} · ${seasonOf(spin)}`}</span>
                {spin.attempt < (keptAttempt.get(spin.round) ?? spin.attempt) ? (
                  <span className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Respun away</span>
                ) : null}
              </p>
              <div className="mt-2 grid gap-3 md:grid-cols-2">
                {spin.quarterbacks.map((quarterback) => (
                  <QuarterbackValues key={quarterback.playerId} quarterback={quarterback} taken={taken} />
                ))}
                <fieldset className="border border-line p-3">
                  <legend className="px-1 font-slab text-base uppercase">The team</legend>
                  <ul>
                    <ValueRow
                      label={SLOT_LABELS.supporting_cast}
                      value={spin.supportingCast}
                      taken={taken?.slot === "supporting_cast"}
                    />
                  </ul>
                </fieldset>
              </div>
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}

function QuarterbackValues({ quarterback, taken }: { quarterback: Quarterback; taken: DraftPick | undefined }) {
  return (
    <fieldset className="border border-line p-3">
      <legend className="px-1 font-slab text-base uppercase">{quarterback.displayName}</legend>
      <ul>
        {QUALITIES.map((quality) => (
          <ValueRow
            key={quality}
            label={SLOT_LABELS[quality]}
            value={quarterback.values?.[quality] ?? null}
            taken={taken?.playerId === quarterback.playerId && taken.slot === quality}
          />
        ))}
      </ul>
    </fieldset>
  );
}

function ValueRow({ label, value, taken }: { label: string; value: number | null; taken: boolean }) {
  return (
    <li className="flex items-baseline justify-between gap-3 py-1">
      <span className="font-mono text-[11px] font-bold tracking-[0.1em] uppercase">{label}</span>
      <span className="flex items-baseline gap-2">
        {taken ? <span className="font-mono text-[10px] tracking-[0.13em] text-hidden-text uppercase">Taken</span> : null}
        {value !== null ? <span className="font-slab text-lg tabular-nums">{value}</span> : null}
      </span>
    </li>
  );
}

/** Below the season: what is particular to whoever is looking, and where to go next. */
function ResultFooter({
  result,
  personalBest,
  isGuest,
  staged,
}: {
  result: SeasonResult;
  personalBest: number | null;
  isGuest: boolean;
  staged: boolean;
}) {
  return (
    <div className="flex flex-col gap-3 border-t border-line pt-4 text-sm leading-6 text-fg-muted">
      {!isGuest && personalBest !== null ? (
        <p>
          Your personal best in {result.mode} mode:{" "}
          <span className="font-slab text-lg text-fg tabular-nums">{oneDecimal(personalBest)}</span>
        </p>
      ) : null}
      {isGuest ? <GuestNudge /> : null}
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
      <Link
        href="/solo"
        className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg"
      >
        {staged ? "Back to solo games" : "Build your own season"}
      </Link>
    </div>
  );
}
