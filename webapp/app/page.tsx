import type { Metadata } from "next";
import Link from "next/link";

import { type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { HuddleFeed } from "@/components/home/HuddleFeed";
import { QuickActions } from "@/components/home/QuickActions";
import { SearchQueryProvider } from "@/components/home/search-context";
import { ActivityFeed } from "@/components/foundation/friends/ActivityFeed";
import { UsernamePrompt } from "@/components/foundation/identity/UsernamePrompt";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { canAnswerPrompt, canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { fetchGameContexts } from "@/lib/foundation/content/nfl/schedule";
import { ACTIVITY_PAGE_SIZE, activityEvents } from "@/lib/foundation/friends/friends";
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
  // Real accounts get a Huddle | Friends switch (?view=friends); guests and
  // signed-out visitors only have the Huddle.
  const hasFriendsTab = canViewProfile(claims);
  const params = await props.searchParams;
  const viewParam = Array.isArray(params.view) ? params.view[0] : params.view;
  const view: HomeView = hasFriendsTab && viewParam === "friends" ? "friends" : "huddle";

  // Independent of each other, so they go together rather than in sequence.
  // The Huddle is readable before a player has an account or a temporary
  // lobby session. The per-player queries remain conditional, but the public
  // feed and its optional schedule treatment always load.
  const [profileResult, room, { posts, gameContexts }, friends, activity] = await Promise.all([
    viewer
      ? supabase.from("profiles").select("display_name, avatar_url, username").eq("id", claims!.sub).single()
      : Promise.resolve({ data: null }),
    viewer ? currentRoom(supabase, claims!.sub) : Promise.resolve(null),
    (view === "friends" ? Promise.resolve([]) : fetchPromptFeed(supabase, viewer ? claims!.sub : null)).then(async (feed) => ({
      posts: feed,
      // Only the games these posts are about, read from the same table the iOS
      // app uses. A schedule outage should never hide the feed; it only drops
      // the venue, kickoff and primetime details from the covers.
      gameContexts: await fetchGameContexts(supabase, feed.flatMap((post) => post.slots.flatMap((slot) => slot.sourceGameId ?? []))).catch(() => []),
    })),
    view === "friends" ? supabase.rpc("list_friends") : null,
    view === "friends" ? supabase.rpc("friend_activity", { p_limit: ACTIVITY_PAGE_SIZE }) : null,
  ]);

  const { displayName, email, avatarUrl } = chromeIdentity(claims, profileResult.data);

  const { error, q } = params;
  const errorText = Array.isArray(error) ? error[0] : error;
  const query = typeof q === "string" ? q : "";
  // Home stays focused on weekly participation: winner picks and the weekly
  // Power Rankings ritual. Other composer-only templates remain out of this
  // dashboard stream while their player experiences are refined.
  const pickPosts = posts.filter(isHomePrompt);

  return (
    <SearchQueryProvider initialQuery={query}>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <PageShell
        variant="dashboard"
        // The tab bar adds 3rem under the top bar, so the page starts lower on md and up. Important, because .app-page is unlayered CSS and would otherwise win.
        className={hasFriendsTab ? "md:pt-[9.75rem]!" : ""}
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
        {hasFriendsTab ? <HomeTabs active={view} /> : null}
        {view === "friends" ? (
          friends?.error || activity?.error ? (
            <EmptyState title="Couldn't load friend activity" className="mt-6">Try again in a moment.</EmptyState>
          ) : (
            <ActivityFeed initial={activityEvents(activity?.data ?? [])} hasFriends={(friends?.data ?? []).length > 0} />
          )
        ) : (
          <HuddleFeed posts={pickPosts} canAnswer={canAnswerPrompt(claims)} gameContexts={gameContexts} />
        )}
      </PageShell>
    </SearchQueryProvider>
  );
}

type HomeView = "huddle" | "friends";

function HomeTabs({ active }: { active: HomeView }) {
  const tabs: { key: HomeView; label: string; href: string }[] = [
    { key: "huddle", label: "Huddle", href: "/" },
    { key: "friends", label: "Friends", href: "/?view=friends" },
  ];
  return (
    <>
      {/* md and up: a bar under the fixed top bar, clear of the sidebar rail. */}
      <nav
        aria-label="Home sections"
        className="fixed top-[68px] right-0 left-[var(--sidebar-w)] z-20 hidden h-12 items-stretch gap-2 border-b border-line bg-surface/95 px-5 backdrop-blur md:flex"
      >
        {tabs.map(({ key, label, href }) => (
          <Link
            key={key}
            href={href}
            aria-current={key === active ? "page" : undefined}
            className={`flex items-center border-b-2 px-4 font-slab text-[17px] tracking-[0.04em] uppercase transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-panel ${
              key === active ? "border-fg text-fg" : "border-transparent text-fg-muted hover:text-fg"
            }`}
          >
            {label}
          </Link>
        ))}
      </nav>
      {/* Below md there is no top bar, so the tabs sit above the feed. */}
      <nav aria-label="Home sections" className="mb-4 flex border border-line md:hidden">
        {tabs.map(({ key, label, href }) => (
          <Link
            key={key}
            href={href}
            aria-current={key === active ? "page" : undefined}
            className={`flex min-h-12 flex-1 items-center justify-center font-slab text-[17px] tracking-[0.04em] uppercase transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-panel ${
              key === active ? "bg-panel text-panel-fg" : "text-fg hover:text-fg-muted"
            }`}
          >
            {label}
          </Link>
        ))}
      </nav>
    </>
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
