import type { Metadata } from "next";
import Link from "next/link";

import { BallKnowerLeaderboard, type LeaderboardRow } from "@/components/foundation/content/leaderboard/BallKnowerLeaderboard";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { parseLeaderboardScope, parseLeaderboardWindow, type Standing } from "@/lib/foundation/content/leaderboard/windows";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Leaderboard" };

/** The Ball Knower leaderboard: resolved prompt points, ranked per window. */
export default async function LeaderboardPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims) || !canViewProfile(claims)) return <SignedOutLeaderboard />;

  const params = await props.searchParams;
  const window = parseLeaderboardWindow(params.window);
  const scope = parseLeaderboardScope(params.scope);

  const [{ data: profile }, board, standingResult] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("ball_knower_leaderboard", { p_window: window, p_scope: scope }),
    supabase.rpc("my_ball_knower_standing", { p_window: window, p_scope: scope }),
  ]);

  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  const standingRow = standingResult.data?.[0];
  const failed = board.error || standingResult.error || !standingRow;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader
          eyebrow="Leaderboard"
          title="Ball Knower"
          description={
            scope === "friends"
              ? "Points from your resolved picks, ranked against your friends."
              : "Points from your resolved picks, ranked against everyone who plays the weekly prompts."
          }
        />
        <div className="mt-6">
          {failed ? (
            <EmptyState title="Couldn't load the leaderboard">Try again in a moment.</EmptyState>
          ) : (
            <BallKnowerLeaderboard
              window={window}
              scope={scope}
              rows={(board.data ?? []).map(toRow)}
              standing={toStanding(standingRow)}
            />
          )}
        </div>
      </PageShell>
    </>
  );
}

function toRow(row: {
  rank: number;
  profile_id: string;
  display_name: string;
  avatar_url: string | null;
  total_points: number;
  scored_picks: number;
  is_me: boolean;
}): LeaderboardRow {
  return {
    rank: row.rank,
    profileId: row.profile_id,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    totalPoints: row.total_points,
    scoredPicks: row.scored_picks,
    isMe: row.is_me,
  };
}

function toStanding(row: {
  status: string;
  rank: number | null;
  total_points: number;
  scored_picks: number;
  ranked_count: number;
  min_picks: number;
}): Standing {
  return {
    status: row.status === "ranked" ? row.status : "unranked",
    rank: row.rank,
    totalPoints: row.total_points,
    scoredPicks: row.scored_picks,
    rankedCount: row.ranked_count,
    minPicks: row.min_picks,
  };
}

function SignedOutLeaderboard() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <PageShell variant="dashboard">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Leaderboard</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">See where you rank</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to see the Ball Knower leaderboard and your place on it.</p>
          <Link
            href="/login?next=/leaderboard"
            className="mt-6 inline-flex bg-panel px-4 py-3 type-label font-bold text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
          >
            Sign in
          </Link>
        </section>
      </PageShell>
    </>
  );
}
