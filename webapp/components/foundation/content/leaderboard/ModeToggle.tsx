import Link from "next/link";

import { QB_MODES, QB_MODE_LABEL, type QbMode } from "@/lib/foundation/content/leaderboard/boards";

/** QB Season Builder's Visible / Hidden switch. The two modes are scored separately, so each is its own board. */
export function ModeToggle({ mode, hrefFor }: { mode: QbMode; hrefFor: (mode: QbMode) => string }) {
  return (
    <nav aria-label="Season mode" className="flex overflow-hidden rounded-card border border-line">
      {QB_MODES.map((key) => {
        const active = key === mode;
        return (
          <Link
            key={key}
            href={hrefFor(key)}
            aria-current={active ? "page" : undefined}
            className={`flex min-h-12 flex-1 items-center justify-center font-slab text-[17px] tracking-[0.04em] uppercase transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg ${
              active ? "bg-hidden text-fg" : "text-fg hover:text-fg-muted"
            }`}
          >
            {QB_MODE_LABEL[key]}
          </Link>
        );
      })}
    </nav>
  );
}
