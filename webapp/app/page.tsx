import type { Metadata } from "next";

import { type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { HuddleFeed } from "@/components/home/HuddleFeed";
import { QuickActions } from "@/components/home/QuickActions";
import { SearchQueryProvider } from "@/components/home/search-context";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { canAnswerPrompt, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { fetchGameContexts } from "@/lib/foundation/content/nfl/schedule";
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

  // Independent of each other, so they go together rather than in sequence.
  // The Huddle is readable before a player has an account or a temporary
  // lobby session. The per-player queries remain conditional, but the public
  // feed and its optional schedule treatment always load.
  const [profileResult, room, { posts, gameContexts }] = await Promise.all([
    viewer
      ? supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single()
      : Promise.resolve({ data: null }),
    viewer ? currentRoom(supabase, claims!.sub) : Promise.resolve(null),
    fetchPromptFeed(supabase, viewer ? claims!.sub : null).then(async (feed) => ({
      posts: feed,
      // Only the games these posts are about, read from the same table the iOS
      // app uses. A schedule outage should never hide the feed; it only drops
      // the venue, kickoff and primetime details from the covers.
      gameContexts: await fetchGameContexts(supabase, feed.flatMap((post) => post.slots.flatMap((slot) => slot.sourceGameId ?? []))).catch(() => []),
    })),
  ]);

  const { displayName, email, avatarUrl } = chromeIdentity(claims, profileResult.data);

  const { error, q } = await props.searchParams;
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

      <PageShell variant="dashboard" data-home-main>
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}
        <div data-home-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0"><HuddleFeed posts={pickPosts} canAnswer={canAnswerPrompt(claims)} gameContexts={gameContexts} /></div>
          <div data-quick-actions className="hidden xl:block"><QuickActions room={room} /></div>
        </div>
      </PageShell>
    </SearchQueryProvider>
  );
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
