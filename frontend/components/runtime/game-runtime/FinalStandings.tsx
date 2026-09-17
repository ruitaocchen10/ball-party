"use client";

import { motion } from "motion/react";
import { useState, type ReactNode } from "react";

import { Card } from "@/components/foundation/ui-kit/Card";
import { Chevron } from "@/components/foundation/ui-kit/Chevron";
import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";
import { countdownDelay, standingsCountdown, winnerPulse } from "@/lib/foundation/ui-kit/motion";

/**
 * One row of a final-standings screen. Deliberately game-agnostic: what a
 * "record" means (win-loss, dollars spent, a streak) differs by game, so
 * `statLine` is handed over pre-formatted rather than built from fields this
 * component would otherwise have to know every game's shape to render.
 * `roster`, likewise, is arbitrary content — a game with no per-user roster
 * (higher-or-lower) just omits it, and the row renders with no disclosure
 * at all rather than an empty one.
 */
export type FinalStandingsRow = {
  userId: string;
  /** 1-based placement. Row 0 in the array is assumed to be the winner —
   * callers sort before handing rows over, the same way every game's own
   * `byPlacement`/tiebreak sort already does. */
  rank: number;
  name: string;
  avatarUrl: string | null;
  isViewer: boolean;
  statLine: ReactNode;
  /** An optional outcome metric that belongs at the far end of a row, before
   * its disclosure control. Games use it for a single primary result without
   * crowding the identity and stat line together. */
  endMetric?: ReactNode;
  roster?: ReactNode;
};

/**
 * The shared shape of every game's ending: a headline naming the winner,
 * then the whole table ranked underneath, each row expandable into that
 * player's roster where the game has one. Rows reveal in countdown order —
 * last place first, the winner last with a small flourish — see
 * `standingsCountdown` for why that reads as suspense instead of just a
 * staggered fade.
 */
export function FinalStandings({
  eyebrow = "Final",
  headline,
  rows,
}: {
  eyebrow?: string;
  headline: string;
  rows: FinalStandingsRow[];
}) {
  return (
    <>
      <header className="flex flex-col gap-2 pt-2">
        <p className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">{eyebrow}</p>
        <h1 className="font-slab text-4xl leading-none uppercase">{headline}</h1>
      </header>

      <ol className="flex flex-col gap-3">
        {rows.map((row, index) => (
          <StandingsRow key={row.userId} row={row} index={index} total={rows.length} />
        ))}
      </ol>
    </>
  );
}

function StandingsRow({ row, index, total }: { row: FinalStandingsRow; index: number; total: number }) {
  const isWinner = row.rank === 1;

  const header = (
    <div className="flex items-center gap-3 px-3.5 py-3.5">
      <span
        className={`w-7 shrink-0 font-mono tabular-nums ${
          isWinner ? "text-lg font-bold text-panel-fg" : "text-sm text-panel-muted"
        }`}
      >
        #{row.rank}
      </span>
      <Avatar name={row.name} avatarUrl={row.avatarUrl} />
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="flex items-center gap-1.5 font-slab text-lg leading-none uppercase">
          <span className="truncate">{row.name}</span>
          {row.isViewer ? (
            <span className="shrink-0 font-mono text-[10px] tracking-[0.13em] text-panel-muted">YOU</span>
          ) : null}
        </span>
        <span className="font-mono text-[11px] tracking-[0.06em] text-panel-muted uppercase">{row.statLine}</span>
      </span>
      {row.endMetric ? <span className="shrink-0">{row.endMetric}</span> : null}
      {row.roster ? (
        <Chevron className="final-standings-chev h-4 w-4 shrink-0 text-fg-muted transition-transform" />
      ) : null}
    </div>
  );

  return (
    <motion.li variants={standingsCountdown(index, total)} initial="initial" animate="animate">
      <motion.div
        variants={isWinner ? winnerPulse : undefined}
        custom={countdownDelay(index, total)}
        initial={isWinner ? "initial" : undefined}
        animate={isWinner ? "animate" : undefined}
        className="rounded-card"
      >
        <Card edge={false} className={isWinner ? "ring-1 ring-panel-fg/20" : undefined}>
          {row.roster ? (
            <details className="final-standings-roster">
              <summary className="cursor-pointer">{header}</summary>
              <div className="border-t border-dashed border-[#c7bfac] px-3.5 pt-2.5 pb-3.5">{row.roster}</div>
            </details>
          ) : (
            header
          )}
        </Card>
      </motion.div>
    </motion.li>
  );
}

/**
 * A bigger, row-native avatar chip — `StripCellAvatar` bakes in the
 * `mx-auto`/`mt-1` positioning its own vertical strip cells need, which
 * fights a horizontal row's own centering instead of helping it, so this
 * repeats its onError-falls-back-to-initials shape rather than reusing it.
 */
function Avatar({ name, avatarUrl }: { name: string; avatarUrl: string | null }) {
  const [failed, setFailed] = useState(false);

  if (avatarUrl && !failed) {
    return (
      <img
        src={avatarUrl}
        alt=""
        onError={() => setFailed(true)}
        className="h-11 w-11 shrink-0 rounded-full object-cover"
      />
    );
  }

  return (
    <span
      aria-hidden="true"
      className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-full"
    >
      <GeneratedAvatar name={name} size={44} className="h-full w-full" />
    </span>
  );
}
