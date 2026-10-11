import type { ReactNode } from "react";

/** The dashboard's sticky secondary rail: a compact task or status panel with
 * one shared rhythm on every app-page workspace. */
export function DashboardRail({
  headingId,
  eyebrow,
  title,
  children,
  note,
  className = "",
}: {
  headingId: string;
  eyebrow: ReactNode;
  title: ReactNode;
  children: ReactNode;
  note?: ReactNode;
  className?: string;
}) {
  return (
    <aside aria-labelledby={headingId} className={`sticky top-[92px] ${className}`}>
      <div className="rounded-card border border-line bg-surface-raised p-4 shadow-well">
        <p className="type-label font-semibold text-hidden-text">{eyebrow}</p>
        <h2 id={headingId} className="mt-1 font-slab text-[27px] leading-none uppercase">{title}</h2>
        {children}
      </div>
      {note ? <p className="px-1 pt-3 type-label-xs leading-4 text-fg-muted">{note}</p> : null}
    </aside>
  );
}
