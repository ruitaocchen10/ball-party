import type { Metadata } from "next";

import { ColumnHead } from "@/components/home/ColumnHead";
import { CurrentRoom, type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { GameGrid } from "@/components/home/GameGrid";
import { JoinRoom } from "@/components/home/JoinRoom";
import { StartRoom } from "@/components/home/StartRoom";
import { WayIn } from "@/components/home/WayIn";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { groupGames } from "@/lib/platform/orchestration/catalog";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { canCreateLobby, isSignedInViewer } from "@/lib/foundation/identity/viewer";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

export const metadata: Metadata = {
  title: "Play with friends",
  description: "Start or join a room and play sports knowledge games with your friends — Higher or Lower, Auction Team Builder, Wavelength and more.",
  alternates: { canonical: "/party" },
};

/**
 * The room flow, and the shop window it leads into: start or join a room,
 * then pick what to play once people are in it. Split out of the home page
 * once Party, Solo and Social each got a section of their own — Party and
 * Social in the sidebar's main nav (see components/layout/Sidebar.tsx), Solo
 * in the rail's own Solo games section — this page is what "Party" points at.
 *
 * Play stayed with Party rather than moving to its own route: a game tile
 * here still just opens a room, so it is the same flow as the action strip
 * above it, not a separate destination the way Solo and Social are.
 */
export default async function PartyPage(props: PageProps<"/party">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);
  const canHost = canCreateLobby(claims);

  // Independent of each other, so they go together rather than in sequence.
  const [profileResult, room] = viewer
    ? await Promise.all([
        supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single(),
        currentRoom(supabase, claims!.sub),
      ])
    : [{ data: null }, null];

  const displayName = profileResult.data?.display_name ?? (viewer ? (claims!.email as string) : null);
  const email = viewer ? ((claims!.email as string | undefined) ?? null) : null;
  const avatarUrl = profileResult.data?.avatar_url ?? null;

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  const live = groupGames().filter((game) => game.status === "live").length;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo={viewer} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <main className="app-page flex-1">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

        <div data-party-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <PageHeader
              eyebrow="Party"
              title={room ? "Your party" : "What are we playing?"}
              description={
                room
                  ? "Your room is ready when everyone is. Start or join another one below when you’re set."
                  : "Start a room for your crew, or use a code to jump into one that’s already going."
              }
            />

            {room ? (
              <div className="xl:hidden">
                <CurrentRoom room={room} headingId="party-room-heading-mobile" />
              </div>
            ) : null}
            <ActionStrip hasRoom={room !== null} canCreateLobby={canHost} />
            {!room ? <PartyGuide className="xl:hidden" /> : null}

            <section className="mt-9" aria-labelledby="play-heading">
              <ColumnHead id="play-heading" title="Choose the vibe" meta={`${live} live`} />
              <GameGrid canCreateLobby={canHost} />
            </section>
          </div>

          <aside className="hidden xl:block">
            <div className="sticky top-[92px]">
              {room ? (
                <CurrentRoom room={room} compact headingId="party-room-heading-rail" />
              ) : (
                <PartyGuide className="xl:mt-0" />
              )}
            </div>
          </aside>
        </div>
      </main>
    </>
  );
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

/**
 * The two ways into a room.
 *
 * Both ways in are panels rather than controls in a row. The page-level
 * heading lives in PageHeader above, leaving this section focused on the
 * actions a player can take.
 *
 * Hosting is the wider cream panel because opening a room is the primary path.
 * Joining remains a dark companion panel, with the code field immediately
 * available. Neither carries the red edge — a room you have not opened yet is
 * not concealed information, and red means one thing here.
 *
 * When you are already in a room the section steps down below that panel and
 * adds a small warning about what either action will cost you.
 *
 * Carries `id="party-heading"` for aria-labelledby-style anchoring — no
 * longer a URL fragment target now that Party is its own route, but still a
 * stable id for the section.
 */
function ActionStrip({
  hasRoom,
  canCreateLobby,
}: {
  hasRoom: boolean;
  canCreateLobby: boolean;
}) {
  return (
    <section id="party-heading" className={hasRoom ? "pt-6" : "pt-8"}>
      {hasRoom ? (
        <>
          <h2 className="font-slab text-2xl leading-[1.02] uppercase sm:text-3xl">Start something else</h2>
          <p className="mt-2.5 max-w-[48ch] text-[15px] leading-[1.6] text-[#bdb9b2]">
            Heads up — starting or joining another room leaves the one above.
          </p>
        </>
      ) : null}

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,1.3fr)_minmax(19rem,0.7fr)] lg:gap-4 xl:gap-5">
        <StartRoom canCreateLobby={canCreateLobby} />

        <WayIn
          kicker="Someone else hosts"
          title="Join with a code"
          body="Got five characters by text? Type them here — you'll land straight in their room."
        >
          <JoinRoom className="w-full" inPanel />
        </WayIn>
      </div>

    </section>
  );
}

/** A short promise of what follows the entry actions, not a tutorial. */
function PartyGuide({ className = "" }: { className?: string }) {
  const steps = [
    ["01", "Get together", "Open a room or use your friend’s code."],
    ["02", "Pick a game", "Choose once everyone has made it in."],
    ["03", "Make it count", "Play the round, settle the score."],
  ];

  return (
    <section aria-label="How party play works" className={`mt-7 border border-line bg-surface-raised p-4 shadow-well ${className}`}>
      <p className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">Game plan</p>
      <h2 className="mt-1 font-slab text-[27px] leading-none uppercase">How it works</h2>
      <ol className="mt-4 border-t border-line">
        {steps.map(([number, title, body]) => (
          <li key={number} className="flex gap-3 border-b border-line py-3.5 last:border-b-0">
            <span className="pt-0.5 font-mono text-[10px] tracking-[0.14em] text-hidden-text">{number}</span>
            <div>
              <h3 className="font-slab text-lg leading-none uppercase">{title}</h3>
              <p className="mt-1 text-[13px] leading-[1.45] text-fg-muted">{body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}
