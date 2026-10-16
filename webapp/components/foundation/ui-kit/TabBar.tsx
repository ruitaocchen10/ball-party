import Link from "next/link";
import type { ReactNode } from "react";

export type TabBarItem = { key: string; label: ReactNode; href: string };

/**
 * Underlined tabs: the active one is red with a 4px red rule under it; the
 * others have none, just a hairline along the bottom of the bar. Each tab is a link, so the page owns which one is
 * active. Used under a profile's header, and attached to the leaderboard's
 * (`PageHeader`'s `tabs` slot).
 */
export function TabBar({ items, active, ariaLabel }: { items: readonly TabBarItem[]; active: string; ariaLabel: string }) {
  return (
    <nav aria-label={ariaLabel} className="flex border-b border-line">
      {items.map((item) => (
        <Link
          key={item.key}
          href={item.href}
          aria-current={item.key === active ? "page" : undefined}
          className={`-mb-px flex min-h-12 flex-1 items-center justify-center border-b-4 px-2 type-label font-bold transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg ${
            item.key === active ? "border-hidden text-hidden-text" : "border-transparent text-fg-muted hover:text-fg"
          }`}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}
