export const PROFILE_TABS = ["stats", "takes", "lists"] as const;
export type ProfileTab = (typeof PROFILE_TABS)[number];

/** `?tab=` on /profile; anything unknown is the Stats tab. */
export function parseProfileTab(value: unknown): ProfileTab {
  const raw = Array.isArray(value) ? value[0] : value;
  return PROFILE_TABS.find((tab) => tab === raw) ?? "stats";
}
