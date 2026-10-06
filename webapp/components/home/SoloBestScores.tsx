import Link from "next/link";

import { DashboardRail } from "@/components/foundation/ui-kit/DashboardRail";

export type SoloBestScore = { game: string; detail?: string; value: number | null };

/**
 * The Solo hub's rail: the viewer's best result in each solo game. `scores` is
 * null when there is nothing to keep for this viewer (signed out or a guest),
 * so the rail says how to start keeping them instead of listing empty rows.
 */
export function SoloBestScores({ scores }: { scores: SoloBestScore[] | null }) {
  return (
    <DashboardRail
      headingId="solo-best-scores-heading"
      eyebrow="Your record"
      title="Best scores"
      note={scores ? "Beat one and it updates here." : undefined}
    >
      <div className="mt-4 border-t border-line">
        {scores ? (
          scores.map((score) => (
            <div key={`${score.game}-${score.detail ?? ""}`} className="flex items-center justify-between gap-3 border-b border-line py-3.5 last:border-b-0">
              <span className="min-w-0">
                <span className="block type-label font-semibold text-fg">{score.game}</span>
                {score.detail ? <span className="mt-0.5 block truncate text-xs text-fg-muted">{score.detail}</span> : null}
              </span>
              <span className={`font-slab text-2xl leading-none tabular-nums ${score.value === null ? "text-fg-muted" : "text-fg"}`}>
                {score.value ?? "—"}
              </span>
            </div>
          ))
        ) : (
          <p className="py-3.5 text-sm leading-6 text-fg-muted">
            <Link href="/login?next=/solo" className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg">Sign in</Link>{" "}
            to keep your best scores.
          </p>
        )}
      </div>
    </DashboardRail>
  );
}
