import Link from "next/link";
import { redirect } from "next/navigation";
import { UserPlus } from "lucide-react";

import { ProfileEditor } from "@/components/foundation/identity/ProfileEditor";
import { ProfileHeader } from "@/components/foundation/identity/ProfileHeader";
import { ProfileHighlightsCard } from "@/components/foundation/identity/ProfileHighlights";
import { SlotFaceC, YourCalls } from "@/components/foundation/content/prompts/SlotFaces";
import { TakePromptStrip } from "@/components/foundation/content/prompts/TakePromptStrip";
import { TakeCard } from "@/components/foundation/content/prompts/TakeCard";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { GuestUpgrade } from "@/components/foundation/identity/GuestUpgrade";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import { completedMatchesFromHistory } from "@/lib/foundation/identity/summary";
import { profileHighlights } from "@/lib/foundation/identity/highlights";
import type { Comment, Post } from "@/lib/foundation/content/prompts/types";
import { parseProfileTab } from "@/lib/foundation/identity/profileTabs";
import { ProfileTabs } from "@/components/foundation/identity/ProfileTabs";
import { ListSummaries } from "@/components/foundation/content/lists/ListSummaries";
import { fetchListPlayers, fetchLists } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/server";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";

/** A player's durable record, kept deliberately separate from a live room. */
export default async function ProfilePage(props: PageProps<"/profile">) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) return <SignedOutProfile />;
  if (!canViewProfile(claims)) return <GuestProfile />;

  const rawTab = (await props.searchParams).tab;
  // Friends used to be a tab here; old links and bookmarks land on its own page.
  if (rawTab === "friends") redirect("/friends");
  const tab = parseProfileTab(rawTab);

  // Each tab fetches only what it shows. Friends and pending requests are read
  // on every tab because the Friends button shows both counts.
  const [{ data: profile }, historyRows, knowerRows, takeRows, promptFeed, friends, requests] = await Promise.all([
    supabase
      .from("profiles")
      .select("display_name, avatar_url, created_at, username")
      .eq("id", claims.sub)
      .single(),
    tab === "stats" ? supabase.rpc("my_match_history") : null,
    tab === "stats" ? supabase.rpc("my_profile_knower_highlights") : null,
    // A take starts a prompt discussion; replies live on its detail page and
    // don't belong in the profile's take history.
    tab === "takes"
      ? supabase
          .from("prompt_comments")
          .select("id, post_id, body, created_at")
          .eq("author_id", claims.sub)
          .is("parent_comment_id", null)
          .order("created_at", { ascending: false })
      : null,
    tab === "takes" ? fetchPromptFeed(supabase, claims.sub) : null,
    supabase.rpc("list_friends"),
    supabase.rpc("list_friend_requests"),
  ]);

  const ownLists = tab === "lists" && profile?.username ? await fetchLists(supabase, profile.username) : null;
  const listPlayers = ownLists
    ? await fetchListPlayers(supabase, ownLists.lists.filter((list) => list.itemKind === "player").flatMap((list) => list.items))
    : {};

  const matches = completedMatchesFromHistory(historyRows?.data ?? []);
  const highlights = profileHighlights(matches, knowerRows?.data ?? []);
  const takeHistory = (takeRows?.data ?? []).flatMap((take) => {
    const post = promptFeed?.find((candidate) => candidate.id === take.post_id);
    const comment = post?.comments.find((candidate) => candidate.id === take.id);
    // Answering leaves an empty take (0208); the history is the ones with words.
    return post && comment && comment.body.trim() ? [{ post, comment }] : [];
  });
  const pendingRequests = (requests.data ?? []).filter((row) => row.direction === "incoming").length;
  const friendCount = friends.error ? null : (friends.data ?? []).length;
  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell
        variant="dashboard"
        rail={
          <aside className="hidden xl:block">
            <div className="sticky top-[92px]">
              <NextGame />
            </div>
          </aside>
        }
      >
        <ProfileHeader
          displayName={displayName}
          avatarUrl={profile?.avatar_url ?? null}
          username={profile?.username ?? null}
          action={
            <>
              <ProfileEditor displayName={displayName} avatarUrl={profile?.avatar_url ?? null} userId={claims.sub} username={profile?.username ?? null} />
              <FriendsButton count={friendCount} pendingRequests={pendingRequests} />
            </>
          }
        />

        <ProfileTabs active={tab} basePath="/profile" />

        {tab === "stats" ? (
          <>
            <ProfileHighlightsCard highlights={highlights} />
            <div className="xl:hidden">
              <NextGame />
            </div>
          </>
        ) : tab === "takes" ? (
          <section aria-labelledby="takes-history-heading" className="pt-2">
            <SectionHeading id="takes-history-heading">Your takes</SectionHeading>
            {takeHistory.length ? (
              <ol className="mt-3 grid gap-3">
                {takeHistory.map((take) => <TakeHistoryItem key={take.comment.id} {...take} avatarUrl={avatarUrl} />)}
              </ol>
            ) : (
              <EmptyTakeHistory />
            )}
          </section>
        ) : (
          <section aria-labelledby="lists-heading" className="pt-2">
            <div className="flex items-baseline justify-between gap-3">
              <SectionHeading id="lists-heading">Your lists</SectionHeading>
              <Link href="/lists" className="type-label text-fg underline underline-offset-2">Build your lists</Link>
            </div>
            {ownLists?.failed ? (
              <EmptyState title="Couldn't load your lists" className="mt-3">Try again in a moment.</EmptyState>
            ) : (
              <ListSummaries lists={ownLists?.lists ?? []} players={listPlayers} emptyText="Rank teams and players, and your lists show up here for friends to see." />
            )}
          </section>
        )}
      </PageShell>
    </>
  );
}

/** Opens the friends page, which holds friends, requests and adding someone. */
function FriendsButton({ count, pendingRequests }: { count: number | null; pendingRequests: number }) {
  return (
    <ButtonLink href="/friends" variant="ghost" fullWidth={false} className="w-[calc(50%-4px)] gap-2 sm:w-44">
      <UserPlus aria-hidden className="h-4 w-4" strokeWidth={2} />
      Friends
      {count !== null ? <span className="font-mono text-[13px] font-bold">{count}</span> : null}
      {pendingRequests > 0 ? (
        <span className="rounded-full bg-hidden px-1.5 font-mono text-[10px] leading-4 text-fg">
          <span className="sr-only">{pendingRequests} pending requests </span>
          <span aria-hidden="true">{pendingRequests}</span>
        </span>
      ) : null}
    </ButtonLink>
  );
}

function GuestProfile() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <PageShell variant="dashboard">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Current game</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Make your record yours</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Your name is just for the current game. Create an account to save a profile and keep your results.</p>
          <div className="mt-6"><GuestUpgrade /></div>
        </section>
      </PageShell>
    </>
  );
}

function SignedOutProfile() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <PageShell variant="dashboard">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Player profile</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Your record starts here</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to keep a record of your games, wins, and streaks.</p>
          <Link href="/login?next=/profile" className="mt-6 inline-flex rounded-card bg-fg px-4 py-3 type-label font-bold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg">Sign in</Link>
        </section>
      </PageShell>
    </>
  );
}

function NextGame() {
  return (
    <section className="rounded-card border border-line bg-surface-raised p-5 text-fg shadow-well sm:p-6">
      <p className="type-label text-fg-muted">Your next game</p>
      <h2 className="mt-2 font-slab text-[25px] leading-[.98] uppercase">Make the record</h2>
      <p className="mt-3 max-w-[32ch] text-sm leading-6 text-fg-muted">
        Every completed game lands here — play with friends, chase a streak, and leave a mark.
      </p>
      <Link
        href="/"
        className="mt-5 inline-flex rounded-card bg-fg px-3.5 py-3 type-label font-bold text-surface transition-colors hover:bg-panel-ink-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
      >
        Find a game
      </Link>
    </section>
  );
}

function SectionHeading({ id, children }: { id: string; children: React.ReactNode }) {
  return <h2 id={id} className="type-label font-bold text-fg-muted">{children}</h2>;
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
        context={<TakePromptStrip postId={post.id} caption={post.caption.trim() || "a prompt"} />}
        commentHref={`/prompts/${post.id}/takes/${comment.id}`}
        collapsedByDefault={hasPickDetails}
      >
        {hasPickDetails ? (
          isPicksPost(post) ? (
            <YourCalls slots={post.slots} responses={post.viewerResponse ?? {}} />
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
  return <EmptyState className="mt-3">No takes yet. Your takes on prompt posts will show up here.</EmptyState>;
}
