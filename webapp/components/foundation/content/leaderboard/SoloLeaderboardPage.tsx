import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { SignedOutLeaderboard } from "@/components/foundation/content/leaderboard/SignedOutLeaderboard";
import { SoloLeaderboard } from "@/components/foundation/content/leaderboard/SoloLeaderboard";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { parseQbMode, SOLO_BOARD_COPY, soloBoardHref, type SoloBoard } from "@/lib/foundation/content/leaderboard/boards";
import { parseLeaderboardScope } from "@/lib/foundation/content/leaderboard/windows";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

const DESCRIPTION: Record<SoloBoard, { all: string; friends: string }> = {
  "higher-or-lower": {
    all: "Your best solo streak, ranked against everyone.",
    friends: "Your best solo streak, ranked against your friends.",
  },
  "qb-season-builder": {
    all: "Your best season score, ranked against everyone.",
    friends: "Your best season score, ranked against your friends.",
  },
};

/**
 * A solo game's all-time best-run board, at /solo/<game>/leaderboard. One page
 * per game; the two routes are thin wrappers so each stays a static segment
 * next to the game's other routes.
 */
export async function SoloLeaderboardPage({
  board,
  searchParams,
}: {
  board: SoloBoard;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims) || !canViewProfile(claims)) {
    return (
      <SignedOutLeaderboard
        next={soloBoardHref({ board })}
        body="Sign in to see the leaderboard and your place on it. Guests aren't ranked."
      />
    );
  }

  const params = await searchParams;
  const scope = parseLeaderboardScope(params.scope);
  // Only QB Season Builder scores more than one mode; the RPC refuses a mode for any other game.
  const mode = board === "qb-season-builder" ? parseQbMode(params.mode) : undefined;
  const { title, game } = SOLO_BOARD_COPY[board];

  const [{ data: profile }, rows, standing] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("solo_leaderboard", { p_game: game, p_mode: mode, p_scope: scope }),
    supabase.rpc("my_solo_standing", { p_game: game, p_mode: mode, p_scope: scope }),
  ]);

  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;
  const standingRow = standing.data?.[0];
  const failed = rows.error || standing.error || !standingRow;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader
          eyebrow="Solo"
          title={title}
          description={DESCRIPTION[board][scope]}
          backHref="/solo"
          backLabel="Solo games"
        />
        <div className="mt-6">
          {failed ? (
            <EmptyState title="Couldn't load the leaderboard">Try again in a moment.</EmptyState>
          ) : (
            <SoloLeaderboard
              board={board}
              mode={mode}
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
              standing={{
                status: standingRow.status === "ranked" ? "ranked" : "unranked",
                rank: standingRow.rank,
                bestScore: standingRow.best_score === null ? null : Number(standingRow.best_score),
                rankedCount: standingRow.ranked_count,
              }}
            />
          )}
        </div>
      </PageShell>
    </>
  );
}
