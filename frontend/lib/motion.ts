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
