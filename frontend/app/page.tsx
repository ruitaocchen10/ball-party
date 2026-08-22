import { CurrentRoom, type RoomSummary } from "@/components/home/CurrentRoom";
import { WayIn } from "@/components/home/WayIn";
import { ButtonLink } from "@/components/ui/Button";
import { ErrorBanner } from "@/components/ui/ErrorBanner";
import { TopBar } from "@/components/layout/TopBar";
import { createClient } from "@/lib/supabase/server";
import { isSignedInViewer } from "@/lib/auth/viewer";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

/**
 * The slim landing page. Party, Solo and Social used to all live here as
 * sections of one long page; each is now its own route (see
 * components/layout/TopBar.tsx), so this keeps only what does not belong to
 * any one of them — the room you are already in, if any, and a way into the
 * three — rather than duplicating their content.
 */
export default async function Home(props: PageProps<"/">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);

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

  return (
    <>
      <TopBar displayName={displayName} />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

        {room ? <CurrentRoom room={room} /> : null}
        <Overview hasRoom={room !== null} />
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
 * The heading, and the three ways in. Steps down the same way Party's action
 * strip used to when a room is already open above it — CurrentRoom's own
 * (screen-reader-only) heading is the page's `<h1>` then, so this demotes to
 * `<h2>` rather than doubling up.
 */
function Overview({ hasRoom }: { hasRoom: boolean }) {
  const Heading = hasRoom ? "h2" : "h1";

  return (
    <section className={hasRoom ? "pt-6" : "pt-10 lg:pt-14"}>
      <Heading
        className={`font-slab leading-[1.02] -skew-x-7 uppercase ${
          hasRoom ? "text-2xl sm:text-3xl" : "text-[34px] sm:text-[43px]"
        }`}
      >
        Where to?
      </Heading>

      <p className={`max-w-[48ch] text-[15px] leading-[1.6] text-[#bdb9b2] ${hasRoom ? "mt-2.5" : "mt-3.5"}`}>
        Start or join a room, play something on your own, or see what&apos;s cooking on Social.
      </p>

      <div className="mt-6 grid gap-3 sm:grid-cols-3 lg:gap-4">
        <WayIn kicker="Start or join" title="Party" body="Open a room, or join one with a code." lit>
          <ButtonLink href="/party" variant="ink" fullWidth={false} className="px-7">
            Go to Party
          </ButtonLink>
        </WayIn>

        <WayIn kicker="Play alone" title="Solo" body="No room needed — jump into a game built for one.">
          <ButtonLink href="/solo" variant="ghost" fullWidth={false} className="px-7">
            Go to Solo
          </ButtonLink>
        </WayIn>

        <WayIn kicker="In development" title="Social" body="A daily prompt to answer and argue about with your group.">
          <ButtonLink href="/social" variant="ghost" fullWidth={false} className="px-7">
            Go to Social
          </ButtonLink>
        </WayIn>
      </div>
    </section>
  );
}
