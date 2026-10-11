import type { ReactNode } from "react";

/**
 * A card is a raised dark surface: a step lighter than the background, with a
 * hairline edge. If something matters it goes on a card; everything else is
 * background.
 *
 * `tone="light"` is the same card in the `fg` cream, for the people in a room
 * (a seat that is taken) against the dark screen and the dark open seats around
 * them. Text on it is `surface`, like a primary button's.
 */
const TONES = {
  panel: "bg-panel text-panel-fg",
  light: "bg-fg text-surface",
} as const;

export function Card({
  children,
  className = "",
  tone = "panel",
}: {
  children: ReactNode;
  className?: string;
  tone?: keyof typeof TONES;
}) {
  return (
    <div
      className={`relative overflow-hidden rounded-card ${TONES[tone]} shadow-card ${className}`}
    >
      {children}
    </div>
  );
}

/** The name on a card: slab, uppercase, and always the biggest thing on it. */
export function CardTitle({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <h2
      className={`px-3 pt-3 pb-1 font-slab text-2xl leading-none uppercase ${className}`}
    >
      {children}
    </h2>
  );
}

/** The line under the name — position, era, matchup, record. */
export function CardMeta({ children }: { children: ReactNode }) {
  return (
    <p className="px-3 pb-3 type-label-lg text-panel-muted">
      {children}
    </p>
  );
}

/**
 * The stat line. Dashed rule above it to separate the identity of the thing
 * from its numbers.
 */
export function CardStats({ children }: { children: ReactNode }) {
  return (
    <dl className="flex justify-between gap-2 border-t border-dashed border-panel-line px-3 pt-2 pb-2.5 font-mono text-[10px] text-panel-muted">
      {children}
    </dl>
  );
}

export function Stat({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex gap-1.5">
      <dt className="uppercase">{label}</dt>
      <dd className="font-bold text-panel-fg tabular-nums">{value}</dd>
    </div>
  );
}
