import type { Metadata } from "next";

import { CurrentRoom, type RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { RoomInvitesInbox } from "@/components/home/RoomInvitesInbox";
import { JoinRoom } from "@/components/home/JoinRoom";
import { StartRoom } from "@/components/home/StartRoom";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { DashboardRail } from "@/components/foundation/ui-kit/DashboardRail";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { toRoomInvite, type RoomInvite } from "@/lib/platform/lobbies/invites";
import { createClient } from "@/lib/supabase/server";
import { canCreateLobby, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

export const metadata: Metadata = {
  title: "Play with friends",
  description: "Start or join a room and play sports knowledge games with your friends — Higher or Lower, Auction Team Builder, Wavelength and more.",
  alternates: { canonical: "/party" },
};

/**
 * The room flow: start a room, or join one by code. The game is picked inside
 * the room once people are in (see GameSelector), so this page doesn't list
 * games. Split out of the home page once Party, Solo and Social each got a
 * section of their own — this page is what "Party" in the sidebar points at.
 */
export default async function PartyPage(props: PageProps<"/party">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);
  const canHost = canCreateLobby(claims);

  // Independent of each other, so they go together rather than in sequence.
  const [profileResult, room, invites] = viewer
    ? await Promise.all([
        supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single(),
        currentRoom(supabase, claims!.sub),
        // Guests have no friends, so nobody can have invited them.
        canHost ? pendingInvites(supabase) : Promise.resolve([]),
      ])
    : [{ data: null }, null, [] as RoomInvite[]];

  const { displayName, email, avatarUrl } = chromeIdentity(claims, profileResult.data);

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <PageShell
        variant="dashboard"
        rail={
          <div className="hidden xl:block">
            {room ? <CurrentRoom room={room} compact headingId="party-room-heading-rail" /> : <PartyGuide />}
          </div>
        }
      >
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

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
        <RoomInvitesInbox invites={invites} hasRoom={room !== null} viewerId={canHost ? claims!.sub : null} />
        <ActionStrip hasRoom={room !== null} canCreateLobby={canHost} />
      </PageShell>
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

/** Pending room invites from friends. A failed read just hides the inbox. */
async function pendingInvites(supabase: Client): Promise<RoomInvite[]> {
  const { data } = await supabase.rpc("list_room_invites");
  return (data ?? []).map(toRoomInvite);
}

/**
 * The two ways into a room: host one, or join one by code.
 *
 * Hosting is the cream card because opening a room is the primary path; joining
 * is its dark companion. Neither carries the red edge: a room you have not
 * opened yet is not concealed information, and red means one thing here. The
 * game is picked inside the room, once people are in (see GameSelector).
 *
 * When you are already in a room the section steps down below it and warns
 * what either action will cost you.
 */
function ActionStrip({ hasRoom, canCreateLobby }: { hasRoom: boolean; canCreateLobby: boolean }) {
  return (
    <section id="party-heading" className={hasRoom ? "pt-6" : "pt-8"}>
      {hasRoom ? (
        <>
          <h2 className="font-slab text-2xl leading-[1.02] uppercase sm:text-3xl">Start something else</h2>
          <p className="mt-2.5 max-w-[48ch] text-[15px] leading-[1.6] text-fg-muted">
            Heads up — starting or joining another room leaves the one above.
          </p>
        </>
      ) : null}

      <div className="mt-6 grid gap-3 sm:grid-cols-2 sm:gap-4">
        <StartRoom canCreateLobby={canCreateLobby} />
        <JoinRoom />
      </div>
    </section>
  );
}

/** A short promise of what follows the entry actions, not a tutorial. */
function PartyGuide() {
  const steps = [
    ["01", "Get together", "Open a room or use your friend’s code."],
    ["02", "Pick a game", "Choose once everyone has made it in."],
    ["03", "Make it count", "Play the round, settle the score."],
  ];

  return (
    <DashboardRail headingId="party-guide-heading" eyebrow="Game plan" title="How it works">
      <ol className="mt-4 border-t border-line">
        {steps.map(([number, title, body]) => (
          <li key={number} className="flex gap-3 border-b border-line py-3.5 last:border-b-0">
            <span className="pt-0.5 type-label text-hidden-text">{number}</span>
            <div>
              <h3 className="font-slab text-lg leading-none uppercase">{title}</h3>
              <p className="mt-1 text-[13px] leading-[1.45] text-fg-muted">{body}</p>
            </div>
          </li>
        ))}
      </ol>
    </DashboardRail>
  );
}
