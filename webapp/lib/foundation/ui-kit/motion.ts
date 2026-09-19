import type { Transition, Variants } from "motion/react";

/**
 * Shared timing so every new JS-driven transition in the app reads as one
 * system instead of each component inventing its own numbers. Durations echo
 * what's already on screen elsewhere: `quick` matches Sidebar's rail-width
 * transition (`transition-[width] duration-150`), `base` matches globals.css's
 * `points-reveal`/`sold-headline` keyframes (360ms), `slow` matches
 * `player-to-roster` (620ms) for a bigger, one-off flourish.
 */
export const DURATION = {
  quick: 0.15,
  base: 0.2,
  slow: 0.32,
} as const;

export const EASE_OUT = [0.16, 1, 0.3, 1] as const;

export const springSnappy: Transition = {
  type: "spring",
  stiffness: 500,
  damping: 34,
};

/** A plain opacity fade — the default for anything with no directional cue. */
export const fade: Variants = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: { duration: DURATION.base, ease: EASE_OUT } },
  exit: { opacity: 0, transition: { duration: DURATION.quick, ease: EASE_OUT } },
};

/** A dropdown/menu panel: fades and scales in from its trigger. */
export const dropdown: Variants = {
  initial: { opacity: 0, scale: 0.96, y: -4 },
  animate: { opacity: 1, scale: 1, y: 0, transition: { duration: DURATION.quick, ease: EASE_OUT } },
  exit: { opacity: 0, scale: 0.96, y: -4, transition: { duration: DURATION.quick, ease: EASE_OUT } },
};

/** Same shape as `dropdown`, anchored below its trigger instead of above. */
export const dropdownUp: Variants = {
  initial: { opacity: 0, scale: 0.96, y: 4 },
  animate: { opacity: 1, scale: 1, y: 0, transition: { duration: DURATION.quick, ease: EASE_OUT } },
  exit: { opacity: 0, scale: 0.96, y: 4, transition: { duration: DURATION.quick, ease: EASE_OUT } },
};

/** A drawer panel sliding in from the left, paired with a fading backdrop. */
export const drawerPanel: Variants = {
  initial: { x: "-100%" },
  animate: { x: 0, transition: { duration: DURATION.slow, ease: EASE_OUT } },
  exit: { x: "-100%", transition: { duration: DURATION.base, ease: EASE_OUT } },
};

export const drawerBackdrop: Variants = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: { duration: DURATION.base } },
  exit: { opacity: 0, transition: { duration: DURATION.base } },
};

/** A concealed value popping into its revealed state — the "sold"/"scored" moment. */
export const reveal: Variants = {
  initial: { opacity: 0, scale: 0.94 },
  animate: { opacity: 1, scale: 1, transition: { duration: DURATION.base, ease: EASE_OUT } },
};

/** An expand/collapse panel (a form replacing a trigger button, and back). */
export const expandCollapse: Variants = {
  initial: { opacity: 0, height: 0 },
  animate: { opacity: 1, height: "auto", transition: { duration: DURATION.base, ease: EASE_OUT } },
  exit: { opacity: 0, height: 0, transition: { duration: DURATION.quick, ease: EASE_OUT } },
};

/** A status/alert line appearing under a form. */
export const message: Variants = {
  initial: { opacity: 0, y: -4 },
  animate: { opacity: 1, y: 0, transition: { duration: DURATION.quick, ease: EASE_OUT } },
  exit: { opacity: 0, y: -4, transition: { duration: DURATION.quick, ease: EASE_OUT } },
};

/** Per-row stagger for a list that reveals itself once, on mount (final standings). */
export function staggerRow(index: number): Variants {
  return {
    initial: { opacity: 0, y: 8 },
    animate: {
      opacity: 1,
      y: 0,
      transition: { duration: DURATION.base, ease: EASE_OUT, delay: index * 0.04 },
    },
  };
}

/**
 * The delay a countdown reveal gives a row at `index` (0 = first place) out
 * of `total` ranked rows. Last place reveals first, at zero delay; first
 * place reveals last. The step between reveals is constant almost the whole
 * way down, then widens for the final two — 2nd, then 1st — so the pause
 * visibly grows right when the winner is about to appear instead of ticking
 * down at the same rate throughout. Exported on its own (not just baked
 * into `standingsCountdown`) so a caller can time a flourish — a glow, a
 * confetti burst — to land exactly when the winner's row does.
 */
export function countdownDelay(index: number, total: number): number {
  const step = 0.16;
  const fromBottom = total - 1 - index;
  const holdBeforeSecond = total >= 2 ? 0.35 : 0;
  const holdBeforeFirst = total >= 1 ? 0.55 : 0;
  const extra =
    fromBottom >= total - 1 && total > 1 ? holdBeforeSecond + holdBeforeFirst
      : fromBottom >= total - 2 ? holdBeforeSecond
      : 0;
  return fromBottom * step + extra;
}

/**
 * A final-standings row, revealed in countdown order (see `countdownDelay`)
 * rather than top-to-bottom. First place gets a small spring overshoot
 * instead of the flat fade every other row gets — the one row this
 * animation exists to build up to should land differently than the rest.
 */
export function standingsCountdown(index: number, total: number): Variants {
  const delay = countdownDelay(index, total);
  const isWinner = index === 0;
  return {
    initial: { opacity: 0, y: 10, scale: isWinner ? 0.9 : 1 },
    animate: {
      opacity: 1,
      y: 0,
      scale: 1,
      transition: isWinner
        ? { type: "spring", stiffness: 340, damping: 20, delay }
        : { duration: DURATION.base, ease: EASE_OUT, delay },
    },
  };
}

/**
 * A one-shot ring pulse for the winner's row, timed (via the `custom` prop
 * carrying a delay from `countdownDelay(0, total)`) to land just after that
 * row's own reveal settles — the flourish that marks it as the answer the
 * countdown was building toward, not just another row in the list.
 */
export const winnerPulse: Variants = {
  initial: { boxShadow: "0 0 0 0 rgba(17,17,17,0)" },
  animate: (delay: number) => ({
    boxShadow: [
      "0 0 0 0 rgba(17,17,17,0)",
      "0 0 0 6px rgba(17,17,17,0.16)",
      "0 0 0 0 rgba(17,17,17,0)",
    ],
    transition: { duration: 0.9, ease: EASE_OUT, delay: delay + DURATION.base, times: [0, 0.45, 1] },
  }),
};

/**
 * Sabotage Draft's tiebreak is a saved playoff sequence. The board settles in
 * after the final standings start their own countdown, then each round and
 * matchup lands in order. These are one-shot outcome reveals, not ambient
 * motion; MotionProvider collapses them for a reduced-motion viewer.
 */
export const tiebreakBoardReveal: Variants = {
  initial: { opacity: 0, y: 14, scale: 0.985 },
  animate: { opacity: 1, y: 0, scale: 1, transition: { duration: DURATION.slow, ease: EASE_OUT, delay: 0.65 } },
};

export function tiebreakRoundReveal(index: number): Variants {
  return {
    initial: { opacity: 0, x: 10 },
    animate: { opacity: 1, x: 0, transition: { duration: DURATION.base, ease: EASE_OUT, delay: 0.92 + index * 0.32 } },
  };
}

export function tiebreakMatchReveal(roundIndex: number, gameIndex: number): Variants {
  return {
    initial: { opacity: 0, y: 8, scale: 0.96 },
    animate: { opacity: 1, y: 0, scale: 1, transition: { duration: DURATION.base, ease: EASE_OUT, delay: 1.04 + roundIndex * 0.32 + gameIndex * 0.1 } },
  };
}
