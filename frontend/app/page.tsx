import { type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { QuickActions } from "@/components/home/QuickActions";
import { SocialFeed } from "@/components/home/SocialFeed";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { canAnswerPrompt, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptFeed } from "@/lib/foundation/content/prompts/feed";
import { fetchNflSchedule } from "@/lib/foundation/content/nfl/schedule";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

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
  const [profileResult, room, posts, schedule] = viewer
    ? await Promise.all([
        supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single(),
        currentRoom(supabase, claims!.sub),
        fetchPromptFeed(supabase, claims!.sub),
        // A schedule outage should never hide the feed; it only removes the
        // optional primetime treatment until the next cached refresh.
        fetchNflSchedule().catch(() => []),
      ])
    : [{ data: null }, null, [], []];

  const displayName = profileResult.data?.display_name ?? (viewer ? (claims!.email as string) : null);
  const email = viewer ? ((claims!.email as string | undefined) ?? null) : null;
  const avatarUrl = profileResult.data?.avatar_url ?? null;

  const { error, q } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;
  const query = typeof q === "string" ? q.trim().toLocaleLowerCase() : "";
  // Home is intentionally the picks surface for now. Other prompt templates
  // remain available to the admin tooling, but do not compete with the
  // picks-prompt UI while that experience is being refined.
  const pickPosts = posts.filter(isPickPrompt);
  const visiblePosts = query
    ? pickPosts.filter((post) => `${post.promptText} ${post.caption} ${post.author}`.toLocaleLowerCase().includes(query))
    : pickPosts;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo={viewer} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <main data-home-main className="app-page flex-1">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}
        <div data-home-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0"><SocialFeed posts={visiblePosts} signedIn={viewer} canAnswer={canAnswerPrompt(claims)} gameContexts={schedule.map(({ id, stadium, kickoff, primetime }) => ({ id, stadium, kickoff, primetime }))} /></div>
          <div data-quick-actions className="hidden xl:block"><QuickActions room={room} /></div>
        </div>
      </main>
    </>
  );
}

/** Older single- and weekly-pick rows remain readable while their data is migrated to `picks`. */
function isPickPrompt(post: { templateKind: string }) {
  return post.templateKind === "picks" || post.templateKind === "game_pick" || post.templateKind === "weekly_picks";
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
