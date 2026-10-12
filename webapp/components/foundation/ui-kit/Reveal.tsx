"use client";

import { AnimatePresence, motion } from "motion/react";
import type { ReactNode } from "react";

import { fade, reveal } from "@/lib/foundation/ui-kit/motion";

/**
 * The concealed → revealed swap used across the match runtimes: a
 * hidden value pops into its true value once the server reveals it —
 * AuctionMatch's fantasy points once a lot sells, HigherOrLowerMatch's
 * challenger score once their card flips. One shared component instead of each
 * runtime inventing its own timing.
 *
 * `revealed` picks which side renders; `concealed` and `children` (the
 * revealed content) crossfade the instant it flips. There's no exit variant
 * on the revealed side on purpose — a concealed→revealed swap never reverses
 * mid-round, so only the concealed side ever needs to leave.
 */
export function Reveal({
  revealed,
  concealed,
  children,
}: {
  revealed: boolean;
  concealed: ReactNode;
  children: ReactNode;
}) {
  return (
    <AnimatePresence mode="wait" initial={false}>
      {revealed ? (
        <motion.div key="revealed" variants={reveal} initial="initial" animate="animate">
          {children}
        </motion.div>
      ) : (
        <motion.div key="concealed" variants={fade} initial="initial" animate="animate" exit="exit">
          {concealed}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
