import { Button, ButtonLink } from "@/components/ui/Button";
import { GameGrid } from "@/components/home/GameGrid";
import { GAMES } from "@/lib/games/catalog";
import { Sidebar } from "@/components/layout/Sidebar";
import { createLobby } from "@/lib/lobbies/actions";
import { createClient } from "@/lib/supabase/server";

export default async function Home(props: PageProps<"/">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  // Mirrors lib/supabase/proxy.ts: an anonymous JWT is signed out, not a user.
  const signedIn = Boolean(claims) && claims?.is_anonymous !== true;

  const { data: profile } = signedIn
    ? await supabase.from("profiles").select("display_name").eq("id", claims!.sub).single()
    : { data: null };

  const displayName = profile?.display_name ?? (signedIn ? (claims!.email as string) : null);

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  return (
    <>
      <Sidebar displayName={displayName} />

      <div className="flex flex-1 flex-col lg:ml-64">
        <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-16 sm:px-6">
          {errorText ? (
            <p
              role="alert"
              className="mt-6 rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
            >
              {errorText}
            </p>
          ) : null}

          {signedIn ? <ActionStrip name={displayName} /> : <Hero />}

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
                3 live · 1 in development
              </span>
            </div>

            <GameGrid signedIn={signedIn} />
          </section>

          {signedIn ? null : <HowItWorks />}
        </main>
      </div>
    </>
  );
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

/** Signed in. No pitch needed — one action, and the games below it. */
function ActionStrip({ name }: { name: string | null }) {
  return (
    <section className="flex flex-col gap-5 border-b border-line pt-7 pb-7 sm:flex-row sm:items-center">
      <div>
        <span className="block font-slab text-2xl leading-none -skew-x-7 uppercase">
          Signed in as {name}
        </span>
        <span className="mt-2 block font-mono text-[10px] tracking-[0.14em] text-fg-muted uppercase">
          Start a room, or join one with a code
        </span>
      </div>

      <div className="flex-1" />

      <form action={createLobby} className="sm:shrink-0">
        <Button type="submit" fullWidth={false} className="w-full px-7 sm:w-auto">
          Start a room
        </Button>
      </form>
    </section>
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
