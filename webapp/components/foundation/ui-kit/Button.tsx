"use client";

import { motion } from "motion/react";
import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode, Ref } from "react";

import { springSnappy } from "@/lib/foundation/ui-kit/motion";

const MotionLink = motion.create(Link);

/**
 * Buttons are cream, because a button is a known thing and everything known in
 * this product sits on a light panel. `ghost` is for the subordinate action on
 * a screen — one primary per view.
 *
 * `ink` inverts that for the one place the rule breaks down: a button sitting
 * ON a cream panel, where cream-on-cream would be invisible. The colours swap;
 * the meaning doesn't.
 *
 * Focus rings are cream rather than red: red is reserved for hidden state, and
 * a focus ring is the opposite of hidden. On a panel it inverts with the rest.
 */
// motion.button redefines these few event props with its own animation-aware
// signatures (see framer-motion's HTMLMotionProps); omitted from the native
// HTML type here so the two declarations don't conflict. Nothing in this app
// wires a CSS animation/drag handler onto a <Button>, so nothing is lost.
type NativeButtonProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "onDrag" | "onDragStart" | "onDragEnd" | "onAnimationStart" | "onAnimationEnd" | "onAnimationIteration"
>;

type Variant = "solid" | "ghost" | "ink" | "text" | "danger";
type Size = "md" | "sm";

type Props = NativeButtonProps & {
  variant?: Variant;
  /** `sm` is the compact mono button for a card or dialog footer, where the
   *  full slab button would out-shout what it sits beside. */
  size?: Size;
  /** Full width is the common case; turn it off to sit inline beside a field. */
  fullWidth?: boolean;
  /** React 19 passes ref through props; it is spread onto the button below.
   *  Declared because the caller needs to return focus here — see BidBar. */
  ref?: Ref<HTMLButtonElement>;
};

// Every Button/ButtonLink in the app is this same element, so the tap
// feedback lands everywhere at once instead of being added button-by-button.
// Skipped while disabled — a control that can't be pressed shouldn't feel
// pressable.
const PRESS = { whileTap: { scale: 0.97 }, transition: springSnappy };

const BASE =
  "cursor-pointer transition-colors disabled:cursor-not-allowed disabled:opacity-60 " +
  "focus-visible:outline-2 focus-visible:outline-offset-2";

const SIZES = {
  md: "min-h-12 px-4 font-slab text-[15px] tracking-[0.04em] uppercase",
  sm: "min-h-9 px-3.5 type-label-lg font-bold",
} as const;

const VARIANTS = {
  solid: "bg-panel text-panel-fg hover:bg-panel-hover focus-visible:outline-panel",
  ghost:
    "bg-transparent text-fg ring-1 ring-line ring-inset hover:bg-surface-raised " +
    "focus-visible:outline-panel",
  ink: "bg-panel-fg text-panel hover:bg-panel-ink-hover focus-visible:outline-panel-fg",
  /** A destructive action, kept subordinate: ghost in the concealed red. */
  danger:
    "bg-transparent text-hidden-text ring-1 ring-hidden/40 ring-inset hover:bg-hidden/10 " +
    "focus-visible:outline-hidden",
  /** No surface at all: "Cancel", "Back". Pair with `fullWidth={false}`. */
  text: "bg-transparent text-fg-muted hover:text-fg focus-visible:outline-panel",
} as const;

export function Button({
  variant = "solid",
  size = "md",
  fullWidth = true,
  className = "",
  children,
  ...props
}: Props) {
  return (
    <motion.button
      {...props}
      {...(props.disabled ? null : PRESS)}
      className={`${BASE} ${SIZES[size]} ${VARIANTS[variant]} ${fullWidth ? "block w-full" : "shrink-0"} ${className}`}
    >
      {children}
    </motion.button>
  );
}

/**
 * A navigation that looks like a button. Separate from <Button> because a
 * <button> inside an <a> is invalid markup, and because the distinction is real
 * — this changes the URL, it does not submit anything.
 */
export function ButtonLink({
  href,
  variant = "solid",
  size = "md",
  fullWidth = true,
  className = "",
  children,
}: {
  href: string;
  variant?: Variant;
  size?: Size;
  fullWidth?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <MotionLink
      href={href}
      {...PRESS}
      className={`${BASE} ${SIZES[size]} ${VARIANTS[variant]} inline-flex items-center justify-center ${
        fullWidth ? "flex w-full" : "shrink-0"
      } ${className}`}
    >
      {children}
    </MotionLink>
  );
}
