import type { Metadata } from "next";

import { SoloLeaderboardPage } from "@/components/foundation/content/leaderboard/SoloLeaderboardPage";

export const metadata: Metadata = { title: "QB Season Builder leaderboard" };

export default function Page(props: PageProps<"/solo/qb-season-builder/leaderboard">) {
  return <SoloLeaderboardPage board="qb-season-builder" searchParams={props.searchParams} />;
}
