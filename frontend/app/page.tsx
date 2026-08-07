import { Button, ButtonLink } from "@/components/ui/Button";
import { CurrentRoom, type RoomSummary } from "@/components/home/CurrentRoom";
import { GameGrid } from "@/components/home/GameGrid";
import { JoinRoom } from "@/components/home/JoinRoom";
import { GAMES } from "@/lib/games/catalog";
import { TopBar } from "@/components/layout/TopBar";
import { createLobby } from "@/lib/lobbies/actions";
import { createClient } from "@/lib/supabase/server";

// The request-scoped client, carrying the generated Database types with it —
// a bare SupabaseClient would erase them and untype every nested select below.
type Client = Awaited<ReturnType<typeof createClient>>;

export default async function Home(props: PageProps<"/">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  // Mirrors lib/supabase/proxy.ts: an anonymous JWT is signed out, not a user.
  const signedIn = Boolean(claims) && claims?.is_anonymous !== true;

  // Independent of each other, so they go together rather than in sequence.
  const [profileResult, room] = signedIn
    ? await Promise.all([
        supabase.from("profiles").select("display_name").eq("id", claims!.sub).single(),
        currentRoom(supabase, claims!.sub),
      ])
    : [{ data: null }, null];

  const displayName = profileResult.data?.display_name ?? (signedIn ? (claims!.email as string) : null);

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  const live = GAMES.filter((game) => game.status === "live").length;
  const upcoming = GAMES.length - live;

  return (
    <>
      <TopBar displayName={displayName} />

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-16 sm:px-6">
        {errorText ? (
          <p
            role="alert"
            className="mt-6 rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
          >
            {errorText}
          </p>
        ) : null}

        {signedIn ? (
          <>
            {room ? <CurrentRoom room={room} /> : null}
            <ActionStrip hasRoom={room !== null} />
          </>
        ) : (
          <Hero />
        )}

        <section aria-labelledby="games-heading">
          <div className="mt-9 mb-4 flex items-baseline gap-3.5">
            <h2
              id="games-heading"
              className="font-slab text-base leading-none -skew-x-7 uppercase sm:text-lg"
            >
              Games
            </h2>
            <span aria-hidden className="h-px flex-1 bg-line" />
            <span className="font-mono text-[9px] tracking-[0.15em] text-fg-muted uppercase">
              {live} live · {upcoming} in development
            </span>
          </div>

          <GameGrid signedIn={signedIn} />
        </section>

        {signedIn ? null : <HowItWorks />}
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
 * Signed out. The pitch is the games themselves, further down — this only has
 * to say what the product is and offer the one action that starts it.
 */
function Hero() {
  return (
    <section className="grid items-center gap-10 pt-10 pb-2 lg:grid-cols-[1fr_480px] lg:gap-8 lg:pt-14">
      <div>
        <p className="mb-3.5 font-mono text-[10px] tracking-[0.19em] text-hidden-text uppercase">
          4 players · 5–15 minutes · nothing to install
        </p>
        <h1 className="mb-4 font-slab text-[34px] leading-[1.02] -skew-x-7 uppercase sm:text-[43px]">
          Find out who
          <br />
          actually knows
          <br />
          ball.
        </h1>
        <p className="mb-6 max-w-[44ch] text-[15px] leading-[1.6] text-[#bdb9b2] sm:text-base">
          Start a room, send the code to three friends, and settle it. Points stay hidden until
          they don&apos;t.
        </p>
        <div className="flex flex-col gap-2.5 sm:flex-row">
          {/* Signed out this navigates rather than submits: creating a room
              needs an account, and a button that fails is worse than a link
              that explains. */}
          <ButtonLink href="/signup" fullWidth={false} className="sm:px-7">
            Start a room
          </ButtonLink>
          <ButtonLink href="#games-heading" variant="ghost" fullWidth={false} className="sm:px-7">
            See the games
          </ButtonLink>
        </div>
        <p className="mt-4 font-mono text-[9px] tracking-[0.13em] text-fg-muted uppercase">
          Sign-in takes about ten seconds · Google or email
        </p>

        {/* The room page opens for people without accounts, so someone who was
            texted a bare code — no link — needs a door here too. */}
        <div className="mt-7 border-t border-line pt-5">
          <p className="mb-2.5 font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
            Already have a code?
          </p>
          <JoinRoom className="w-full sm:w-fit" />
        </div>
      </div>

      <Fan />
    </section>
  );
}

/**
 * Decoration, and the only place the product shows its hand before you sign in:
 * three things you can see and one you can't.
 *
 * The geometry is load-bearing. Each card is 120px wide but sits 118px from the
 * last, so only 118px of it is ever visible before the next one covers it, and
 * `overflow-hidden` silently eats whatever doesn't fit. Everything printed on a
 * card has to clear that wedge minus 16px of padding — measured, not guessed:
 * "Wavelength" is the widest string at 91px and the wedge gives it 102px.
 * The red back counts as a neighbour, so its offset constrains the last face.
 */
function Fan() {
  const faces = GAMES.filter((game) => game.status === "live").slice(0, 3);
  const offsets = ["left-0 top-5 -rotate-9", "left-[118px] top-1.5 -rotate-2", "left-[236px] top-4 rotate-6"];

  return (
    <div aria-hidden className="relative hidden h-[210px] lg:block">
      {faces.map((game, i) => (
        <div
          key={game.slug}
          className={`absolute h-[178px] w-[120px] overflow-hidden rounded-card bg-panel text-panel-fg shadow-card ${offsets[i]}`}
        >
          <span className="block h-[5px] bg-hidden" />
          <p className="px-2 pt-2.5 font-slab text-[11px] leading-[1.1] -skew-x-7 uppercase">
            {game.shortName.map((line) => (
              <span key={line} className="block">
                {line}
              </span>
            ))}
          </p>
          <p className="px-2 pt-1.5 font-mono text-[7px] tracking-[0.1em] text-panel-muted uppercase">
            {game.players}
          </p>
        </div>
      ))}
      <div className="pattern-concealed absolute top-[32px] left-[354px] h-[178px] w-[120px] rotate-[13deg] rounded-card bg-hidden shadow-concealed">
        <span className="pointer-events-none absolute inset-[5px] rounded-[3px] border border-panel/35" />
      </div>
    </div>
  );
}

/**
 * Signed in: the heading, and the two ways into a room.
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
 */
function ActionStrip({ hasRoom }: { hasRoom: boolean }) {
  const Heading = hasRoom ? "h2" : "h1";

  return (
    <section className={hasRoom ? "pt-6" : "pt-10 lg:pt-14"}>
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

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:gap-4">
        <WayIn
          kicker="You host"
          title="Start a room"
          body="Opens a five-character code. Send it to three friends and pick a game once they're in."
          lit
        >
          <form action={createLobby}>
            <Button type="submit" variant="ink" fullWidth={false} className="px-7">
              Start a room
            </Button>
          </form>
        </WayIn>

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

/** One of the two panels. `lit` is the cream one — there is only ever one. */
function WayIn({
  kicker,
  title,
  body,
  lit = false,
  children,
}: {
  kicker: string;
  title: string;
  body: string;
  lit?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`flex flex-col rounded-card p-4 sm:p-[18px] ${
        lit
          ? "bg-panel text-panel-fg shadow-card"
          : "bg-surface-raised ring-1 ring-line ring-inset"
      }`}
    >
      <p
        className={`font-mono text-[10px] tracking-[0.16em] uppercase ${
          lit ? "text-hidden-ink" : "text-hidden-text"
        }`}
      >
        {kicker}
      </p>
      <h3 className="mt-2.5 font-slab text-xl leading-none -skew-x-7 uppercase sm:text-[22px]">
        {title}
      </h3>
      <p
        className={`mt-2.5 text-[13.5px] leading-[1.5] ${lit ? "text-[#4c4739]" : "text-[#a5a29c]"}`}
      >
        {body}
      </p>

      {/* Pinned to the bottom so the two controls line up when the copy above
          them wraps to different heights. */}
      <div className="mt-4 pt-1 sm:mt-auto">{children}</div>
    </div>
  );
}

/** Only shown signed out: someone with an account already knows this. */
function HowItWorks() {
  const steps = [
    {
      n: "01 · the room",
      title: "Open a room",
      body: "One code, four players, no mode yet. The room is durable — it survives whatever you decide to play.",
    },
    {
      n: "02 · arcade",
      title: "One game, quick",
      body: "Pick a single game from inside the room. Everyone's still here after, so pick another.",
    },
    {
      n: "03 · party",
      title: "Race to the score",
      body: "Minigames back to back, points carry, first to the target wins.",
    },
  ];

  return (
    <section aria-labelledby="how-heading" className="mt-11">
      <div className="mb-4 flex items-baseline gap-3.5">
        <h2
          id="how-heading"
          className="font-slab text-base leading-none -skew-x-7 uppercase sm:text-lg"
        >
          Two ways to play
        </h2>
        <span aria-hidden className="h-px flex-1 bg-line" />
      </div>

      <ul className="grid gap-3 sm:grid-cols-3 lg:gap-4">
        {steps.map((step) => (
          <li
            key={step.n}
            className="rounded border border-line bg-surface-raised px-4 pt-3.5 pb-4"
          >
            <p className="mb-2 font-mono text-[9px] tracking-[0.17em] text-hidden-text uppercase">
              {step.n}
            </p>
            <h3 className="mb-1.5 font-slab text-[15px] leading-[1.1] -skew-x-7 uppercase">
              {step.title}
            </h3>
            <p className="text-[12.5px] leading-[1.55] text-[#a5a29c]">{step.body}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}
