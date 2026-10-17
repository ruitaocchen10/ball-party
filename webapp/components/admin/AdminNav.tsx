"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/**
 * The only nav admin screens get — a plain row of tabs, not the consumer
 * app's Sidebar. This isn't consumer chrome, so it doesn't pretend to be:
 * no brand rail, no account menu, just where the admin sections are.
 */
const ADMIN_NAV_ITEMS = [
  { href: "/admin", label: "Calendar" },
  { href: "/admin/prompts", label: "Compose" },
  { href: "/admin/queue", label: "Queue" },
  { href: "/admin/posts", label: "Posts" },
  { href: "/admin/reports", label: "Reports" },
  { href: "/admin/design", label: "Design" },
];

export function AdminNav() {
  const pathname = usePathname();

  return (
    <nav aria-label="Admin sections" className="flex gap-1 border-b border-line px-4 sm:px-6">
      {ADMIN_NAV_ITEMS.map(({ href, label }) => {
        const active = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`border-b-2 px-3 py-3 font-mono text-[11px] tracking-[0.12em] uppercase transition-colors ${
              active ? "border-fg text-fg" : "border-transparent text-fg-muted hover:text-fg"
            }`}
          >
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
