import type { ReactNode } from "react";

/**
 * A small label that tags a thing: "You", "Complete", "Locked". It names a
 * state; it is not a control, so it never takes a click.
 *
 * Tones follow the rest of the kit. `solid` is a cream chip, the strongest
 * one, for the viewer's own mark. `soft` is the same cream as an outline.
 * `muted` and `outline` sit quietly on the background. `success` is the green
 * of a completed state, and `hidden` is red, which is reserved for concealed
 * things, so use it only for those.
 *
 * `xs` is the denser size, for chips that sit beside a heading or a stat.
 */
type Tone = "solid" | "soft" | "muted" | "outline" | "success" | "hidden";

const TONES: Record<Tone, string> = {
  solid: "bg-panel text-panel-fg",
  soft: "border border-panel/50 bg-panel/10 text-panel",
  muted: "bg-surface text-fg-muted ring-1 ring-line ring-inset",
  outline: "border border-fg-muted/50 bg-surface text-fg-muted",
  success: "bg-grade-elite text-panel-hover",
  hidden: "bg-hidden text-panel/90",
};

const SIZES = {
  xs: "type-label-xs px-2 py-1 leading-none",
  sm: "type-label px-1.5 py-0.5",
} as const;

export function Badge({
  tone = "solid",
  size = "sm",
  icon,
  className = "",
  children,
}: {
  tone?: Tone;
  size?: keyof typeof SIZES;
  icon?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <span
      className={`inline-flex shrink-0 items-center gap-1 font-bold ${TONES[tone]} ${SIZES[size]} ${className}`.trim()}
    >
      {icon}
      {children}
    </span>
  );
}
