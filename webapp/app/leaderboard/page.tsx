import type { Metadata } from "next";
import Link from "next/link";

import { BallKnowerLeaderboard, type LeaderboardRow } from "@/components/foundation/content/leaderboard/BallKnowerLeaderboard";
import { GamerLeaderboard } from "@/components/foundation/content/leaderboard/GamerLeaderboard";
import { BoardNav } from "@/components/foundation/content/leaderboard/LeaderboardParts";
import { SoloLeaderboard } from "@/components/foundation/content/leaderboard/SoloLeaderboard";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import {
  boardHref,
  LEADERBOARD_BOARD_COPY,
  parseLeaderboardBoard,
  parseQbMode,
  soloGameFor,
  type GamerStanding,
  type LeaderboardBoard,
  type QbMode,
  type SoloStanding,
} from "@/lib/foundation/content/leaderboard/boards";
import { parseLeaderboardScope, parseLeaderboardWindow, type LeaderboardScope, type LeaderboardWindow, type Standing } from "@/lib/foundation/content/leaderboard/windows";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Leaderboard" };

const BOARD_DESCRIPTION = {
  "ball-knower": {
    all: "Points from your resolved picks, ranked against everyone who plays the weekly prompts.",
    friends: "Points from your resolved picks, ranked against your friends.",
  },
  gamer: {
    all: "Multiplayer wins, ranked against everyone who plays in rooms.",
    friends: "Multiplayer wins, ranked against your friends.",
  },
  "higher-or-lower": {
    all: "Your best solo streak, ranked against everyone.",
    friends: "Your best solo streak, ranked against your friends.",
  },
  "qb-season-builder": {
    all: "Your best season score, ranked against everyone.",
    friends: "Your best season score, ranked against your friends.",
  },
} as const;

/** The leaderboards: Ball Knower points, multiplayer wins, and an all-time best board per solo game. */
export default async function LeaderboardPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims) || !canViewProfile(claims)) return <SignedOutLeaderboard />;

  const params = await props.searchParams;
  const board = parseLeaderboardBoard(params.board);
  const window = parseLeaderboardWindow(params.window);
  const scope = parseLeaderboardScope(params.scope);
  const mode = parseQbMode(params.mode);

  const { data: profile } = await supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single();

  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  const content = await loadBoard(supabase, { board, window, scope, mode });

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader
          eyebrow="Leaderboard"
          title={LEADERBOARD_BOARD_COPY[board].title}
          description={BOARD_DESCRIPTION[board][scope]}
        />
        <div className="mt-6">
          <BoardNav board={board} hrefFor={(key) => boardHref({ board: key, scope })} />
          {content ?? <EmptyState title="Couldn't load the leaderboard">Try again in a moment.</EmptyState>}
        </div>
      </PageShell>
    </>
  );
}

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** The selected board, or null when either of its two reads failed. */
async function loadBoard(
  supabase: Supabase,
  { board, window, scope, mode }: { board: LeaderboardBoard; window: LeaderboardWindow; scope: LeaderboardScope; mode: QbMode },
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

  if (board === "gamer") {
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

  const game = soloGameFor(board);
  if (!game) return null;
  const soloMode = board === "qb-season-builder" ? mode : undefined;
  const [rows, standing] = await Promise.all([
    supabase.rpc("solo_leaderboard", { p_game: game, p_mode: soloMode, p_scope: scope }),
    supabase.rpc("my_solo_standing", { p_game: game, p_mode: soloMode, p_scope: scope }),
  ]);
  const standingRow = standing.data?.[0];
  if (rows.error || standing.error || !standingRow) return null;
  return (
    <SoloLeaderboard
      board={board}
      mode={soloMode}
      scope={scope}
      rows={(rows.data ?? []).map((row) => ({
        rank: row.rank,
        profileId: row.profile_id,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        bestScore: Number(row.best_score),
        isMe: row.is_me,
        username: row.is_me ? null : row.username,
      }))}
      standing={toSoloStanding(standingRow)}
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

function toSoloStanding(row: { status: string; rank: number | null; best_score: number | null; ranked_count: number }): SoloStanding {
  return {
    status: row.status === "ranked" ? row.status : "unranked",
    rank: row.rank,
    bestScore: row.best_score === null ? null : Number(row.best_score),
    rankedCount: row.ranked_count,
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
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to see the leaderboards and your place on them.</p>
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
