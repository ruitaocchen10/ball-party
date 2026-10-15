import Link from "next/link";

import { PROFILE_TABS, type ProfileTab } from "@/lib/foundation/identity/profileTabs";

const TAB_LABEL: Record<ProfileTab, string> = { stats: "Stats", takes: "Takes", lists: "Lists" };

/**
 * Stats, Takes and Lists under a profile's header. Your own profile and
 * another player's use the same bar; `basePath` is the page it lives on
 * (`/profile` or `/u/<name>`), and Stats is the bare path.
 */
export function ProfileTabs({ active, basePath }: { active: ProfileTab; basePath: string }) {
  return (
    <nav aria-label="Profile sections" className="flex border-b border-line">
      {PROFILE_TABS.map((key) => (
        <Link
          key={key}
          href={key === "stats" ? basePath : `${basePath}?tab=${key}`}
          aria-current={key === active ? "page" : undefined}
          className={`-mb-px flex min-h-12 flex-1 items-center justify-center border-b-2 type-label font-bold transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg ${
            key === active ? "border-hidden text-fg" : "border-transparent text-fg-muted hover:text-fg"
          }`}
        >
          {TAB_LABEL[key]}
        </Link>
      ))}
    </nav>
  );
}
