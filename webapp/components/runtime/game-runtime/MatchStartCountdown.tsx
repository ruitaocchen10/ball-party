"use client";

import { AnimatePresence, motion } from "motion/react";

import { START_LEAD_SECONDS, useMatchStartCountdown } from "@/lib/runtime/game-runtime/useMatchStartCountdown";
import { EASE_OUT } from "@/lib/foundation/ui-kit/motion";
import { GAMES, matchGameName, type MatchGame } from "@/lib/platform/orchestration/catalog";

/**
 * The 3-2-1 over a room match before play begins. The timing is the server's
 * (see `useMatchStartCountdown`); this only draws it. Render it beside the
 * game's own screen: it covers the page while it runs and is nothing after.
 * Same look as the iOS `StartCountdownView`.
 */
export function MatchStartCountdown({ matchId, game }: { matchId: string; game: MatchGame }) {
  const count = useMatchStartCountdown(matchId);
  const info = GAMES.find((candidate) => candidate.match === game);
  const title = matchGameName(game);

  return (
    <AnimatePresence>
      {count !== null ? (
        <motion.div
          key="match-start-countdown"
          role="status"
          aria-label={`${title} starts in ${count}`}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2, ease: EASE_OUT }}
          className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-6 bg-surface px-8"
        >
          <p className="type-label-lg font-bold text-fg-muted">Starting in</p>
          <div className="relative flex size-52 items-center justify-center">
            <svg viewBox="0 0 100 100" className="absolute inset-0 -rotate-90" aria-hidden="true">
              <circle cx="50" cy="50" r="46" fill="none" strokeWidth="3" className="stroke-line" />
              <motion.circle
                cx="50"
                cy="50"
                r="46"
                fill="none"
                strokeWidth="3"
                className="stroke-fg"
                pathLength={1}
                strokeDasharray="1 1"
                animate={{ strokeDashoffset: 1 - count / START_LEAD_SECONDS }}
                transition={{ duration: 0.4, ease: "easeInOut" }}
              />
            </svg>
            <AnimatePresence mode="popLayout" initial={false}>
              <motion.span
                key={count}
                aria-hidden="true"
                initial={{ opacity: 0, y: -14 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 14 }}
                transition={{ duration: 0.25, ease: EASE_OUT }}
                className="font-slab text-9xl leading-none tabular-nums text-fg"
              >
                {count}
              </motion.span>
            </AnimatePresence>
          </div>
          <div className="flex flex-col items-center gap-1.5 text-center">
            <h1 className="font-slab text-3xl uppercase leading-none text-fg">{title}</h1>
            {info ? <p className="type-label text-fg-muted">{info.tagline}</p> : null}
          </div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}
