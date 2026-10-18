import type { Metadata } from "next";
import Link from "next/link";

import { type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { HuddleFeed } from "@/components/home/HuddleFeed";
import { QuickActions } from "@/components/home/QuickActions";
import { SearchQueryProvider } from "@/components/home/search-context";
import { InviteBar } from "@/components/foundation/friends/InviteBar";
import { UsernamePrompt } from "@/components/foundation/identity/UsernamePrompt";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { canAnswerPrompt, canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { fetchGameContexts } from "@/lib/foundation/content/nfl/schedule";
import { fetchListPlayers, fetchListUpdates } from "@/lib/foundation/lists/server";
import { ACTIVITY_PAGE_SIZE, activityEvents, answerersByPost, parseHomeFilter, type HomeFilter } from "@/lib/foundation/friends/friends";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

// Home also answers to ?q= and ?error=, which are the same page for a crawler.
export const metadata: Metadata = { alternates: { canonical: "/" } };

/**
 * The signed-in home is a compact dashboard: the Huddle is the central,
 * interactive stream, while navigation and party/solo actions sit around it.
 */
export default async function Home(props: PageProps<"/">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);
  // Real accounts get filter pills (?filter=prompts|friends) over the one feed;
  // guests and signed-out visitors only have the prompts.
  const hasFriendsFilter = canViewProfile(claims);
  const params = await props.searchParams;
  const filterParam = Array.isArray(params.filter) ? params.filter[0] : params.filter;
  const filter = parseHomeFilter(filterParam, hasFriendsFilter);
  // Game moments page by `?before=<occurred_at of the oldest one shown>`; prompts and moments older than it fill the next page.
  const beforeParam = Array.isArray(params.before) ? params.before[0] : params.before;
  const before = filter !== "prompts" && hasFriendsFilter && typeof beforeParam === "string" && !Number.isNaN(Date.parse(beforeParam)) ? beforeParam : null;
  const wantsFriends = hasFriendsFilter && filter !== "prompts" && filter !== "lists";
  // Shared list updates (yours and your friends') sit in the feed beside prompts and game moments.
  const wantsUpdates = hasFriendsFilter && filter !== "prompts";

  // Independent of each other, so they go together rather than in sequence.
  // The Huddle is readable before a player has an account or a temporary
  // lobby session. The per-player queries remain conditional, but the public
  // feed and its optional schedule treatment always load.
  const [profileResult, room, { posts, gameContexts, answerers }, friends, activity, listUpdates, inviteCodeResult] = await Promise.all([
    viewer
      ? supabase.from("profiles").select("display_name, avatar_url, username").eq("id", claims!.sub).single()
      : Promise.resolve({ data: null }),
    viewer ? currentRoom(supabase, claims!.sub) : Promise.resolve(null),
    fetchPromptFeed(supabase, viewer ? claims!.sub : null).then(async (feed) => {
      const [gameContexts, answered] = await Promise.all([
        // Only the games these posts are about, read from the same table the iOS
        // app uses. A schedule outage should never hide the feed; it only drops
        // the venue, kickoff and primetime details from the covers.
        fetchGameContexts(supabase, feed.flatMap((post) => post.slots.flatMap((slot) => slot.sourceGameId ?? []))).catch(() => []),
        wantsFriends && feed.length ? supabase.rpc("friends_who_answered", { p_post_ids: feed.map((post) => post.id) }) : null,
      ]);
      return { posts: feed, gameContexts, answerers: answerersByPost(answered?.data ?? []) };
    }),
    wantsFriends ? supabase.rpc("list_friends") : null,
    wantsFriends ? supabase.rpc("friend_activity", { p_limit: ACTIVITY_PAGE_SIZE, ...(before ? { p_before: before } : {}) }) : null,
    wantsUpdates ? fetchListUpdates(supabase, { limit: LIST_UPDATE_PAGE_SIZE, before }) : Promise.resolve([]),
    // The invite bar is on every pill for a real account; the code is created on first use.
    hasFriendsFilter ? supabase.rpc("get_my_friend_code") : null,
  ]);
  const inviteCode = inviteCodeResult?.data ?? null;
  const listPlayers = await fetchListPlayers(supabase, listUpdates.filter((update) => update.itemKind === "player").flatMap((update) => [...update.items, ...(update.previousItems ?? [])]));

  const { displayName, email, avatarUrl } = chromeIdentity(claims, profileResult.data);

  const { error, q } = params;
  const errorText = Array.isArray(error) ? error[0] : error;
  const query = typeof q === "string" ? q : "";
  // Home stays focused on weekly participation: winner picks and the weekly
  // Power Rankings ritual. Other composer-only templates remain out of this
  // dashboard stream while their player experiences are refined.
  const pickPosts = posts.filter(isHomePrompt);
  const activityFeedEvents = activityEvents(activity?.data ?? []);

  return (
    <SearchQueryProvider initialQuery={query}>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <PageShell
        variant="dashboard"
        rail={<div className="hidden xl:block"><QuickActions room={room} /></div>}
      >
        {canViewProfile(claims) && profileResult.data?.username ? (
          <UsernamePrompt
            userId={claims!.sub}
            currentUsername={profileResult.data.username}
            preferredUsername={preferredUsername(claims)}
          />
        ) : null}
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}
        <PageHeader eyebrow="Social" title="The huddle" />
        {hasFriendsFilter ? <HomeFilters active={filter} /> : null}
        {inviteCode ? <InviteBar code={inviteCode} /> : null}
        {friends?.error || activity?.error ? (
          <EmptyState title="Couldn't load friend activity" className="mt-6">Try again in a moment.</EmptyState>
        ) : (
          <HuddleFeed
            posts={pickPosts}
            canAnswer={canAnswerPrompt(claims)}
            gameContexts={gameContexts}
            filter={filter}
            answerers={answerers}
            moments={activityFeedEvents}
            before={before}
            pageFull={(activity?.data ?? []).length >= ACTIVITY_PAGE_SIZE}
            hasFriends={(friends?.data ?? []).length > 0}
            listUpdates={listUpdates}
            listPlayers={listPlayers}
            viewerId={viewer ? claims!.sub : null}
            listUpdatesFull={listUpdates.length >= LIST_UPDATE_PAGE_SIZE}
          />
        )}
      </PageShell>
    </SearchQueryProvider>
  );
}

const FILTERS: { key: HomeFilter; label: string; href: string }[] = [
  { key: "all", label: "All", href: "/" },
  { key: "prompts", label: "Prompts", href: "/?filter=prompts" },
  { key: "friends", label: "Friends", href: "/?filter=friends" },
  { key: "lists", label: "Lists", href: "/?filter=lists" },
];

const LIST_UPDATE_PAGE_SIZE = 20;

function HomeFilters({ active }: { active: HomeFilter }) {
  return (
    <nav aria-label="Filter the feed" className="mt-4 flex gap-2">
      {FILTERS.map(({ key, label, href }) => (
        <Link
          key={key}
          href={href}
          aria-current={key === active ? "page" : undefined}
          className={`flex min-h-10 items-center rounded-full border px-4 type-label transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg ${
            key === active ? "border-fg bg-fg text-surface" : "border-line text-fg hover:text-fg-muted"
          }`}
        >
          {label}
        </Link>
      ))}
    </nav>
  );
}

/** The username typed at signup (kept in user metadata until the email is confirmed), if it differs from the assigned one. */
function preferredUsername(claims: { user_metadata?: unknown } | undefined) {
  const metadata = claims?.user_metadata as { username?: unknown } | undefined;
  return typeof metadata?.username === "string" ? metadata.username : null;
}

/** Older single- and weekly-pick rows remain readable while their data is migrated to `picks`. */
function isHomePrompt(post: { templateKind: string }) {
  return post.templateKind === "picks" || post.templateKind === "game_pick" || post.templateKind === "weekly_picks" || post.templateKind === "weekly_awards" || post.templateKind === "power_rankings" || post.templateKind === "bold_predictions";
}

/**
 * The one room the viewer is currently in, or null.
 *
 * No filter on membership is needed: RLS only returns lobbies where
 * is_lobby_member() holds for the caller, and a player is in exactly one at a
 * time. `closed_at` is the filter that matters — since migration 0006 a
 * host-closed room keeps its members attached, so without it a dead room would
 * keep showing up here forever.
 */
async function currentRoom(supabase: Client, userId: string): Promise<RoomSummary | null> {
  const { data: lobby } = await supabase
    .from("lobbies")
    .select("code, host_id, lobby_members(user_id, joined_at, left_at, profiles(display_name))")
    .is("closed_at", null)
    .limit(1)
    .maybeSingle();

  if (!lobby) return null;

  const players = lobby.lobby_members
    .filter((member) => member.left_at === null)
    .sort((a, b) => a.joined_at.localeCompare(b.joined_at))
    .map((member) => ({
      id: member.user_id,
      name: member.profiles?.display_name ?? "Unknown player",
    }));

  return { code: lobby.code, players, hostId: lobby.host_id, youId: userId };
}
