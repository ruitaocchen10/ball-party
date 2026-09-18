"use client";

import { AnimatePresence, motion } from "motion/react";
import type { ReactNode } from "react";

import { message } from "@/lib/foundation/ui-kit/motion";

/**
 * The one-line status/error paragraph that shows up under nearly every form
 * in the app (ProfileEditor, GuestUpgrade, GuestJoin, AuthForm, the higher-or-
 * lower call window, the sabotage draft board) — always the same shape: a
 * `role="alert"`/`role="status"` `<p>` that's there conditionally, appearing
 * the instant something goes wrong or succeeds. Wraps that one pattern once
 * instead of every call site inventing its own `AnimatePresence` + variant.
 *
 * `children` doubles as the presence check: pass the message string directly
 * (or `null`/`undefined` when there's nothing to show) rather than gating the
 * component with a ternary at the call site — that keeps the `key` this needs
 * for AnimatePresence to detect a *new* message (not just a still-present one)
 * in one place.
 */
export function AnimatedMessage({
  children,
  role = "status",
  className = "",
}: {
  children: ReactNode;
  role?: "alert" | "status";
  className?: string;
}) {
  return (
    <AnimatePresence mode="wait">
      {children ? (
        <motion.p
          key={typeof children === "string" ? children : "message"}
          role={role}
          variants={message}
          initial="initial"
          animate="animate"
          exit="exit"
          className={className}
        >
          {children}
        </motion.p>
      ) : null}
    </AnimatePresence>
  );
}
