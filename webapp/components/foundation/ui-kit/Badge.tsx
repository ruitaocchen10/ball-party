import type { ReactNode } from "react";

/**
 * A small label that tags a thing: "You", "Complete", "Locked". It names a
 * state; it is not a control, so it never takes a click.
 *
 * Tones follow the rest of the kit. `solid` is a light chip, the strongest
 * one, for the viewer's own mark. `soft` is the same light tone as an outline.
 * `muted` and `outline` sit quietly on the background. `success` is the green
 * of a completed state, and `hidden` is red, which is reserved for concealed
 * things, so use it only for those. `ink` is a dark chip for sitting on a
 * light card. `scrim` is a dark, blurred chip for sitting on top of art (a
 * prompt card's timer), where a flat tone would vanish into whatever is behind.
 *
 * `xs` is the denser size, for chips that sit beside a heading or a stat.
 */
type Tone = "solid" | "soft" | "muted" | "outline" | "success" | "hidden" | "ink" | "scrim";

const TONES: Record<Tone, string> = {
  solid: "bg-fg text-surface",
  soft: "border border-fg/50 bg-fg/10 text-fg",
  muted: "bg-surface text-fg-muted ring-1 ring-line ring-inset",
  outline: "border border-fg-muted/50 bg-surface text-fg-muted",
  success: "bg-grade-elite text-fg",
  hidden: "bg-hidden text-fg/90",
  ink: "bg-surface text-fg",
  scrim: "bg-surface/80 text-fg ring-1 ring-line ring-inset backdrop-blur-sm",
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
      className={`inline-flex shrink-0 items-center gap-1 rounded-chip font-bold ${TONES[tone]} ${SIZES[size]} ${className}`.trim()}
    >
      {icon}
      {children}
    </span>
  );
}
