import type { Metadata } from "next";

import { SoloLeaderboardPage } from "@/components/foundation/content/leaderboard/SoloLeaderboardPage";

export const metadata: Metadata = { title: "Higher or Lower leaderboard" };

export default function Page(props: PageProps<"/solo/higher-or-lower/leaderboard">) {
  return <SoloLeaderboardPage board="higher-or-lower" searchParams={props.searchParams} />;
}
