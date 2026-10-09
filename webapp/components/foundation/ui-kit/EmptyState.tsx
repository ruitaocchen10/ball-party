import type { ReactNode } from "react";

/**
 * What a list or feed shows when there is nothing in it yet. A passive notice,
 * so it is a well rather than a raised card: see `--shadow-well`. Say what is
 * missing and, if it helps, when it will fill in.
 */
export function EmptyState({
  title,
  children,
  className = "",
}: {
  title?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`rounded-card bg-surface-raised px-5 py-8 text-center shadow-well ${className}`.trim()}>
      {title ? <p className="font-slab text-2xl uppercase">{title}</p> : null}
      <p className={`mx-auto max-w-sm text-sm leading-6 text-fg-muted ${title ? "mt-2" : ""}`}>{children}</p>
    </div>
  );
}
