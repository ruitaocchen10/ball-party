"use client";

import { useRouter } from "next/navigation";

import { Select } from "@/components/foundation/ui-kit/Select";
import { LEADERBOARD_WINDOWS, LEADERBOARD_WINDOW_COPY, type LeaderboardWindow } from "@/lib/foundation/content/leaderboard/windows";

/** The time window as a dropdown. Picking one navigates to that window's URL, so the board stays a server page. */
export function WindowSelect({ window, hrefs }: { window: LeaderboardWindow; hrefs: Record<LeaderboardWindow, string> }) {
  const router = useRouter();
  return (
    <Select
        name="window"
        ariaLabel="Time window"
        variant="dark"
        value={window}
        onValueChange={(value) => router.push(hrefs[value as LeaderboardWindow])}
        options={LEADERBOARD_WINDOWS.map((key) => ({ value: key, label: LEADERBOARD_WINDOW_COPY[key].label }))}
    />
  );
}
