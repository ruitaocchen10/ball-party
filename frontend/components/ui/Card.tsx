import type { ReactNode } from "react";

/**
 * A card is the only light surface in the product. If something matters it goes
 * on a card; everything else is background.
 *
 * The red strip along the top edge marks a card that has concealed information
 * behind it, which is why it doesn't break the rule that red means hidden. Pass
 * `edge={false}` when nothing is being withheld.
 */
export function Card({
  children,
  edge = true,
  className = "",
}: {
  children: ReactNode;
  edge?: boolean;
  className?: string;
}) {
  return (
    <div
      className={`relative overflow-hidden rounded-card bg-panel text-panel-fg shadow-card ${className}`}
    >
      {edge && <span aria-hidden className="block h-[5px] bg-hidden" />}
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
      className={`px-3 pt-3 pb-1 font-slab text-2xl leading-none -skew-x-7 uppercase ${className}`}
    >
      {children}
    </h2>
  );
}

/** The line under the name — position, era, matchup, record. */
export function CardMeta({ children }: { children: ReactNode }) {
  return (
    <p className="px-3 pb-3 font-mono text-[11px] tracking-[0.11em] text-panel-muted uppercase">
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
    <dl className="flex justify-between gap-2 border-t border-dashed border-[#c7bfac] px-3 pt-2 pb-2.5 font-mono text-[10px] text-panel-muted">
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
