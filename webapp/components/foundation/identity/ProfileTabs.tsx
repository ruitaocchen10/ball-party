import { TabBar } from "@/components/foundation/ui-kit/TabBar";
import { PROFILE_TABS, type ProfileTab } from "@/lib/foundation/identity/profileTabs";

const TAB_LABEL: Record<ProfileTab, string> = { stats: "Stats", takes: "Takes", lists: "Lists" };

/**
 * Stats, Takes and Lists under a profile's header. Your own profile and
 * another player's use the same bar; `basePath` is the page it lives on
 * (`/profile` or `/u/<name>`), and Stats is the bare path.
 */
export function ProfileTabs({ active, basePath }: { active: ProfileTab; basePath: string }) {
  return (
    <TabBar
      ariaLabel="Profile sections"
      active={active}
      items={PROFILE_TABS.map((key) => ({ key, label: TAB_LABEL[key], href: key === "stats" ? basePath : `${basePath}?tab=${key}` }))}
    />
  );
}
