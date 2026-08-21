import { CurrentRoom, type RoomSummary } from "@/components/home/CurrentRoom";
import { GameGrid } from "@/components/home/GameGrid";
import { JoinRoom } from "@/components/home/JoinRoom";
import { SoloGrid } from "@/components/home/SoloGrid";
import { StartRoom } from "@/components/home/StartRoom";
import { TalkPreview } from "@/components/home/TalkPreview";
import { WayIn } from "@/components/home/WayIn";
import { GAMES } from "@/lib/games/catalog";
import { TopBar } from "@/components/layout/TopBar";
import { createClient } from "@/lib/supabase/server";
import { canCreateLobby, isSignedInViewer } from "@/lib/auth/viewer";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

export default async function Home(props: PageProps<"/">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);
  const canHost = canCreateLobby(claims);

  // Independent of each other, so they go together rather than in sequence.
  const [profileResult, room] = viewer
    ? await Promise.all([
        supabase.from("profiles").select("display_name").eq("id", claims!.sub).single(),
        currentRoom(supabase, claims!.sub),
      ])
    : [{ data: null }, null];

  const displayName = profileResult.data?.display_name ?? (viewer ? (claims!.email as string) : null);

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  const live = GAMES.filter((game) => game.status === "live").length;
  const upcoming = GAMES.length - live;
  const soloLive = GAMES.filter((game) => game.solo && game.status === "live").length;

  return (
    <>
      <TopBar displayName={displayName} />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20">
        {errorText ? (
          <p
            role="alert"
            className="mt-6 rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
          >
            {errorText}
          </p>
        ) : null}

        {room ? <CurrentRoom room={room} /> : null}
        <ActionStrip hasRoom={room !== null} canCreateLobby={canHost} />

        <section className="mt-9" aria-labelledby="play-heading">
          <ColumnHead
            id="play-heading"
            title="Play"
            meta={`${live} live · ${upcoming} in development`}
          />
          <GameGrid canCreateLobby={canHost} />
        </section>

        {/* Solo and Social as two even columns: the smaller of the room's two
            offshoots — one real game deep, one nothing behind it yet — so
            neither one is stretched to carry a full-width section on its
            own. Social has nothing behind it yet, so it gets an
            honestly-empty placeholder instead of a column pretending to be
            real — see TalkPreview. */}
        <section className="mt-9 grid grid-cols-1 gap-x-8 gap-y-9 lg:grid-cols-2 lg:gap-x-10">
          <div aria-labelledby="solo-heading">
            <ColumnHead id="solo-heading" title="Solo" meta={`${soloLive} live`} />
            <SoloGrid canPlaySolo={viewer} />
          </div>

          <div aria-labelledby="social-heading">
            <ColumnHead id="social-heading" title="Social" meta="In development" />
            <TalkPreview />
          </div>
        </section>
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
 * A column's heading: title, a hairline to fill the rest of the row, and a
 * status line flush right. Pulled out of the old single "Games" section
 * heading so Play and Talk render it identically.
 */
function ColumnHead({ id, title, meta }: { id: string; title: string; meta: string }) {
  return (
    <div className="mb-4 flex items-baseline gap-3.5">
      <h2 id={id} className="font-slab text-base leading-none -skew-x-7 uppercase sm:text-lg">
        {title}
      </h2>
      <span aria-hidden className="h-px flex-1 bg-line" />
      <span className="font-mono text-[9px] tracking-[0.15em] text-fg-muted uppercase">
        {meta}
      </span>
    </div>
  );
}

/**
 * The heading, and the two ways into a room.
 *
 * Both ways in are panels rather than controls in a row. The heading used to
 * read "signed in as <name>" with the actions squeezed beside it — the largest
 * type on the page spending itself on a fact the top bar already carries, and
 * the two things you actually came to do reading as toolbar furniture.
 *
 * Hosting is the cream panel because cream is what this product gives the thing
 * that matters. Joining is the same size on a dark one: equal standing, clear
 * emphasis. Neither carries the red edge — a room you have not opened yet is
 * not concealed information, and red means one thing here.
 *
 * When you are already in a room the whole section steps down: the panel above
 * is the important object, so the heading shrinks and says what these two
 * buttons will cost you.
 *
 * Carries `id="party-heading"` for the top bar's "Party" link — this is the
 * actual room flow the nav points at, whatever the heading above happens to
 * say at the moment.
 */
function ActionStrip({
  hasRoom,
  canCreateLobby,
}: {
  hasRoom: boolean;
  canCreateLobby: boolean;
}) {
  const Heading = hasRoom ? "h2" : "h1";

  return (
    <section id="party-heading" className={hasRoom ? "pt-6" : "pt-10 lg:pt-14"}>
      <Heading
        className={`font-slab leading-[1.02] -skew-x-7 uppercase ${
          hasRoom ? "text-2xl sm:text-3xl" : "text-[34px] sm:text-[43px]"
        }`}
      >
        {hasRoom ? (
          "Start something else"
        ) : (
          <>
            What are we
            <br />
            playing?
          </>
        )}
      </Heading>

      <p
        className={`max-w-[48ch] text-[15px] leading-[1.6] text-[#bdb9b2] ${
          hasRoom ? "mt-2.5" : "mt-3.5"
        }`}
      >
        {hasRoom
          ? "Heads up — starting or joining another room leaves the one above."
          : "Two ways in. Everything else happens once people are in the room."}
      </p>

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:gap-4 xl:gap-5">
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
