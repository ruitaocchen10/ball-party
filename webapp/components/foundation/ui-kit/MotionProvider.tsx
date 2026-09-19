"use client";

import { MotionConfig } from "motion/react";

/**
 * One place that tells every `motion.*` element and `AnimatePresence` in the
 * app to honor the OS's reduced-motion setting. Without this, each new
 * animation would need its own `motion-safe:`-style guard — the way the
 * CSS keyframes in globals.css do today — repeated at every call site.
 * `"user"` (rather than `"always"`) means viewers who haven't opted into
 * reduced motion keep the full transitions; only `prefers-reduced-motion:
 * reduce` collapses them to instant.
 */
export function MotionProvider({ children }: { children: React.ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
