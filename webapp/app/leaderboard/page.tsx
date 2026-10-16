import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { BallKnowerLeaderboard, type LeaderboardRow } from "@/components/foundation/content/leaderboard/BallKnowerLeaderboard";
import { GamerLeaderboard } from "@/components/foundation/content/leaderboard/GamerLeaderboard";
import { ScopeToggle } from "@/components/foundation/content/leaderboard/LeaderboardParts";
import { WindowSelect } from "@/components/foundation/content/leaderboard/WindowSelect";
import { SignedOutLeaderboard } from "@/components/foundation/content/leaderboard/SignedOutLeaderboard";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { TabBar } from "@/components/foundation/ui-kit/TabBar";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import {
  asSoloBoard,
  boardHref,
  LEADERBOARD_BOARDS,
  LEADERBOARD_BOARD_COPY,
  parseLeaderboardBoard,
  parseQbMode,
  soloBoardHref,
  type GamerStanding,
  type LeaderboardBoard,
} from "@/lib/foundation/content/leaderboard/boards";
import { LEADERBOARD_WINDOWS, parseLeaderboardScope, parseLeaderboardWindow, type LeaderboardScope, type LeaderboardWindow, type Standing } from "@/lib/foundation/content/leaderboard/windows";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Leaderboard" };

/**
 * The leaderboards: Ball Knower points and multiplayer wins. The solo games'
 * all-time best boards live with the games, at /solo/<game>/leaderboard.
 */
export default async function LeaderboardPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims) || !canViewProfile(claims)) {
    return <SignedOutLeaderboard next="/leaderboard" body="Sign in to see the leaderboards and your place on them." />;
  }

  const params = await props.searchParams;
  const scope = parseLeaderboardScope(params.scope);

  // The solo boards used to be tabs here; send an old link to the game's own page.
  const soloBoard = asSoloBoard(params.board);
  if (soloBoard) redirect(soloBoardHref({ board: soloBoard, scope, mode: parseQbMode(params.mode) }));

  const board = parseLeaderboardBoard(params.board);
  const window = parseLeaderboardWindow(params.window);

  const { data: profile } = await supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single();

  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  const content = await loadBoard(supabase, { board, window, scope });

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader title="Leaderboard" />
        <div className="mt-4">
          <TabBar
            ariaLabel="Leaderboard"
            active={board}
            items={LEADERBOARD_BOARDS.map((key) => ({ key, label: LEADERBOARD_BOARD_COPY[key].label, href: boardHref({ board: key, scope }) }))}
          />
          <div className="mt-4 flex items-center justify-between gap-3">
            <ScopeToggle scope={scope} hrefFor={(key) => boardHref({ board, window, scope: key })} />
            <WindowSelect window={window} hrefs={Object.fromEntries(LEADERBOARD_WINDOWS.map((key) => [key, boardHref({ board, window: key, scope })])) as Record<LeaderboardWindow, string>} />
          </div>
          <div className="mt-4">{content ?? <EmptyState title="Couldn't load the leaderboard">Try again in a moment.</EmptyState>}</div>
        </div>
      </PageShell>
    </>
  );
}

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** The selected board, or null when either of its two reads failed. */
async function loadBoard(
  supabase: Supabase,
  { board, window, scope }: { board: LeaderboardBoard; window: LeaderboardWindow; scope: LeaderboardScope },
) {
  if (board === "ball-knower") {
    const [rows, standing] = await Promise.all([
      supabase.rpc("ball_knower_leaderboard", { p_window: window, p_scope: scope }),
      supabase.rpc("my_ball_knower_standing", { p_window: window, p_scope: scope }),
    ]);
    const standingRow = standing.data?.[0];
    if (rows.error || standing.error || !standingRow) return null;
    return <BallKnowerLeaderboard window={window} scope={scope} rows={(rows.data ?? []).map(toRow)} standing={toStanding(standingRow)} />;
  }

  const [rows, standing] = await Promise.all([
    supabase.rpc("gamer_leaderboard", { p_window: window, p_scope: scope }),
    supabase.rpc("my_gamer_standing", { p_window: window, p_scope: scope }),
  ]);
  const standingRow = standing.data?.[0];
  if (rows.error || standing.error || !standingRow) return null;
  return (
    <GamerLeaderboard
      window={window}
      scope={scope}
      rows={(rows.data ?? []).map((row) => ({
        rank: row.rank,
        profileId: row.profile_id,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        wins: row.wins,
        gamesPlayed: row.games_played,
        isMe: row.is_me,
        username: row.is_me ? null : row.username,
      }))}
      standing={toGamerStanding(standingRow)}
    />
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
  username: string | null;
}): LeaderboardRow {
  return {
    rank: row.rank,
    profileId: row.profile_id,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    totalPoints: row.total_points,
    scoredPicks: row.scored_picks,
    isMe: row.is_me,
    username: row.is_me ? null : row.username,
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

function toGamerStanding(row: {
  status: string;
  rank: number | null;
  wins: number;
  games_played: number;
  ranked_count: number;
  min_wins: number;
}): GamerStanding {
  return {
    status: row.status === "ranked" ? row.status : "unranked",
    rank: row.rank,
    wins: row.wins,
    gamesPlayed: row.games_played,
    rankedCount: row.ranked_count,
    minWins: row.min_wins,
  };
}
