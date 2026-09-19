import Link from "next/link";

import { ProfileEditor } from "@/components/foundation/identity/ProfileEditor";
import { ProfileHeader } from "@/components/foundation/identity/ProfileHeader";
import { ProfileHighlightsCard, type ProfileHighlights } from "@/components/foundation/identity/ProfileHighlights";
import { SlotFaceC, YourCalls } from "@/components/foundation/content/prompts/SlotFaces";
import { TakeCard } from "@/components/foundation/content/prompts/TakeCard";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { GuestUpgrade } from "@/components/foundation/identity/GuestUpgrade";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import { completedMatchesFromHistory, profileStatRanges, summarizeMultiplayerProfileRange, type CompletedMatchWithMode } from "@/lib/foundation/identity/summary";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";
import { createClient } from "@/lib/supabase/server";

/** A player's durable record, kept deliberately separate from a live room. */
export default async function ProfilePage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) return <SignedOutProfile />;
  if (!canViewProfile(claims)) return <GuestProfile />;

  const [{ data: profile }, { data: historyRows }, { data: knowerRows }, { data: takeRows }, promptFeed] = await Promise.all([
    supabase
      .from("profiles")
      .select("display_name, avatar_url, created_at")
      .eq("id", claims.sub)
      .single(),
    supabase.rpc("my_match_history"),
    supabase.rpc("my_profile_knower_highlights"),
    // A take starts a prompt discussion; replies live on its detail page and
    // don't belong in the profile's take history.
    supabase
      .from("prompt_comments")
      .select("id, post_id, body, created_at")
      .eq("author_id", claims.sub)
      .is("parent_comment_id", null)
      .order("created_at", { ascending: false }),
    fetchPromptFeed(supabase, claims.sub),
  ]);

  const matches = completedMatchesFromHistory(historyRows ?? []);
  const highlights = profileHighlights(matches, knowerRows ?? []);
  const takeHistory = (takeRows ?? []).flatMap((take) => {
    const post = promptFeed.find((candidate) => candidate.id === take.post_id);
    const comment = post?.comments.find((candidate) => candidate.id === take.id);
    return post && comment ? [{ post, comment }] : [];
  });
  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <main className="app-page flex-1">
        <div data-profile-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <div className="max-w-[760px]">
              <ProfileHeader
                displayName={displayName}
                avatarUrl={profile?.avatar_url ?? null}
                joinedLabel={`Playing since ${joinedMonth(profile?.created_at)}`}
                action={<ProfileEditor displayName={displayName} avatarUrl={profile?.avatar_url ?? null} userId={claims.sub} />}
              />

              <ProfileHighlightsCard highlights={highlights} />

              <div className="xl:hidden">
                <NextGame />
              </div>

              <section aria-labelledby="takes-history-heading" className="pt-7">
                <SectionHeading id="takes-history-heading">Your takes</SectionHeading>
                {takeHistory.length ? (
                  <ol className="mt-3 grid gap-3">
                    {takeHistory.map((take) => <TakeHistoryItem key={take.comment.id} {...take} avatarUrl={avatarUrl} />)}
                  </ol>
                ) : (
                  <EmptyTakeHistory />
                )}
              </section>
            </div>
          </div>

          <aside className="hidden xl:block">
            <div className="sticky top-[92px]">
              <NextGame />
            </div>
          </aside>
        </div>
      </main>
    </>
  );
}

function GuestProfile() {
  return (
    <>
      {/* A guest has a real session for playing, just not an account — the
          same floor playSolo itself checks — so the Solo games links work here. */}
      <Sidebar canPlaySolo />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <main className="app-page flex-1">
        <section className="max-w-xl">
          <p className="font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">Current game</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Make your record yours</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Your name is just for the current game. Create an account to save a profile and keep your results.</p>
          <div className="mt-6"><GuestUpgrade /></div>
        </section>
      </main>
    </>
  );
}

function SignedOutProfile() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <main className="app-page flex-1">
        <section className="max-w-xl">
          <p className="font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">Player profile</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Your record starts here</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to keep a record of your games, wins, and streaks.</p>
          <Link href="/login?next=/profile" className="mt-6 inline-flex bg-panel px-4 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">Sign in</Link>
        </section>
      </main>
    </>
  );
}

function NextGame() {
  return (
    <section className="rounded-card border border-line bg-surface-raised p-5 text-fg shadow-well sm:p-6">
      <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">Your next game</p>
      <h2 className="mt-2 font-slab text-[25px] leading-[.98] uppercase">Make the record</h2>
      <p className="mt-3 max-w-[32ch] text-sm leading-6 text-fg-muted">
        Every completed game lands here — play with friends, chase a streak, and leave a mark.
      </p>
      <Link
        href="/"
        className="mt-5 inline-flex bg-panel px-3.5 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-panel-shade focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
      >
        Find a game
      </Link>
    </section>
  );
}

function SectionHeading({ id, children }: { id: string; children: React.ReactNode }) {
  return <h2 id={id} className="font-mono text-[10px] font-bold tracking-[0.15em] text-fg-muted uppercase">{children}</h2>;
}

function TakeHistoryItem({
  post,
  comment,
  avatarUrl,
}: {
  post: Post;
  comment: Comment;
  avatarUrl: string | null;
}) {
  const hasPickDetails = comment.postedWithPick && post.viewerAnswered;

  return (
    <li className="grid gap-2">
      <TakeCard
        comment={comment}
        isYou
        avatarUrl={avatarUrl}
        commentHref={`/prompts/${post.id}/takes/${comment.id}`}
        collapsedByDefault={hasPickDetails}
      >
        {hasPickDetails ? (
          isPicksPost(post) ? (
            <YourCalls slots={post.slots} responses={post.viewerResponse ?? {}} resolved={post.status === "resolved"} />
          ) : (
            <div className="flex flex-col gap-4 px-4 pt-4">
              {post.slots.map((slot) => (
                <SlotFaceC key={slot.id} slot={slot} disabled response={post.viewerResponse?.[slot.id] ?? []} onChange={() => {}} allResponses={post.viewerResponse ?? {}} />
              ))}
            </div>
          )
        ) : null}
      </TakeCard>
    </li>
  );
}

function EmptyTakeHistory() {
  return <div className="mt-3 rounded-card bg-surface-raised px-5 py-6 text-sm leading-6 text-fg-muted shadow-well">No takes yet. Your takes on prompt posts will show up here.</div>;
}

function joinedMonth(date?: string) { return date ? new Intl.DateTimeFormat("en", { month: "long", year: "numeric" }).format(new Date(date)) : "today"; }

function profileHighlights(
  matches: CompletedMatchWithMode[],
  knowerRows: { window_key: string; total_points: number; percentile: number | null }[],
): ProfileHighlights {
  const knowerByRange = new Map(knowerRows.map((row) => [row.window_key, row]));
  const now = new Date();

  return {
    knower: Object.fromEntries(profileStatRanges.map((range) => {
      const row = knowerByRange.get(range);
      return [range, { totalPoints: row?.total_points ?? 0, percentile: row?.percentile ?? null }];
    })) as ProfileHighlights["knower"],
    gamer: Object.fromEntries(profileStatRanges.map((range) => {
      const summary = summarizeMultiplayerProfileRange(matches, range, now);
      return [range, { gamesPlayed: summary.gamesPlayed, wins: summary.wins, winRate: summary.winRate }];
    })) as ProfileHighlights["gamer"],
  };
}
