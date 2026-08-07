import Link from "next/link";

import { Sidebar } from "@/components/layout/Sidebar";
import { Button, ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import { LobbyRealtime } from "@/components/lobby/LobbyRealtime";
import { closeLobby, joinLobby, leaveLobby } from "@/lib/lobbies/actions";
import { createClient } from "@/lib/supabase/server";

const CAPACITY = 4;

export default async function LobbyPage(props: PageProps<"/lobby/[code]">) {
  const { code: rawCode } = await props.params;
  const code = rawCode.trim().toUpperCase();

  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  // Mirrors the rule in lib/supabase/proxy.ts: an anonymous JWT is signed out,
  // not a user. Both places have to agree or this route becomes the one way in.
  // Written as a narrowing guard rather than a boolean so `claims.sub` below
  // needs no non-null assertion.
  //
  // The invite link is the front door, so it opens for people without accounts.
  // RLS tells us nothing about the room from here — a public preview of who is
  // already in it needs its own RPC — so this says only what it can stand
  // behind: the code they were given, and the one action that gets them in.
  if (!claims || claims.is_anonymous === true) {
    const next = encodeURIComponent(`/lobby/${code}`);
    return (
      <Shell code={code} error={errorText}>
        <p className="text-sm leading-6 text-fg-muted">
          You&apos;ve been invited to this room. Sign in to join it — you&apos;ll come straight
          back here.
        </p>
        <div className="flex flex-col gap-2.5">
          <ButtonLink href={`/login?next=${next}`}>Sign in</ButtonLink>
          <ButtonLink href={`/signup?next=${next}`} variant="ghost">
            Create an account
          </ButtonLink>
        </div>
      </Shell>
    );
  }

  // The sidebar shows who you are on every screen, so the viewer's own name is
  // needed here whether or not they turn out to be in this room.
  const { data: viewer } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", claims.sub)
    .single();
  const displayName = viewer?.display_name ?? (claims.email as string | undefined) ?? null;

  // RLS returns nothing for a room you are not a member of, so maybeSingle()
  // rather than single() — "no row" is a normal state here, not a failure. It
  // also means we cannot tell a bad code from a room we haven't joined, which
  // is why both fall through to the join prompt and let the RPC decide.
  const { data: lobby } = await supabase
    .from("lobbies")
    .select(
      "id, code, host_id, closed_at, lobby_members(user_id, joined_at, left_at, profiles(display_name))",
    )
    .eq("code", code)
    .maybeSingle();

  if (!lobby) {
    return (
      <Shell code={code} error={errorText} displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">You&apos;re not in this room yet.</p>
        <form action={joinLobby}>
          <input type="hidden" name="code" value={code} />
          <Button type="submit">Join room</Button>
        </form>
        <HomeLink />
      </Shell>
    );
  }

  if (lobby.closed_at) {
    return (
      <Shell code={code} error={errorText} displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">This room has closed.</p>
        <HomeLink />
      </Shell>
    );
  }

  const members = lobby.lobby_members
    .filter((m) => m.left_at === null)
    .sort((a, b) => a.joined_at.localeCompare(b.joined_at));

  const isHost = lobby.host_id === claims.sub;
  const emptySeats = Math.max(0, CAPACITY - members.length);

  return (
    <Shell code={code} error={errorText} displayName={displayName}>
      <LobbyRealtime lobbyId={lobby.id} />

      <Label>
        {members.length} of {CAPACITY} players
      </Label>

      {/* Players who've arrived are shown on a panel. Spots nobody has filled are
          red — same rule as everywhere else: red means not yet revealed. */}
      <ul className="flex flex-col gap-2.5">
        {members.map((m) => (
          <li key={m.user_id}>
            <Card>
              <div className="flex items-baseline justify-between gap-3 px-3 pt-2.5 pb-3">
                <span className="font-slab text-xl leading-none -skew-x-7 uppercase">
                  {m.profiles?.display_name ?? "Unknown player"}
                </span>
                <span className="font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
                  {[
                    m.user_id === lobby.host_id ? "host" : null,
                    m.user_id === claims.sub ? "you" : null,
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </span>
              </div>
            </Card>
          </li>
        ))}

        {Array.from({ length: emptySeats }, (_, i) => (
          <li key={`empty-${i}`}>
            <Concealed label="Open spot, waiting for a player" className="flex h-[52px] items-center">
              <span className="relative w-full text-center font-mono text-[10px] tracking-[0.15em] text-panel/85 uppercase">
                Open spot
              </span>
            </Concealed>
          </li>
        ))}
      </ul>

      <div className="mt-2 flex flex-col gap-2.5">
        <form action={leaveLobby}>
          <input type="hidden" name="lobby_id" value={lobby.id} />
          <Button type="submit" variant="ghost">
            Leave room
          </Button>
        </form>

        {isHost ? (
          <form action={closeLobby}>
            <input type="hidden" name="lobby_id" value={lobby.id} />
            <input type="hidden" name="code" value={code} />
            {/* Destructive, so it's kept visually subordinate and set apart from
                the action above it. Red doubles as the danger colour here. */}
            <Button
              type="submit"
              variant="ghost"
              className="text-hidden-text ring-hidden/40 hover:bg-hidden/10"
            >
              Close room for everyone
            </Button>
          </form>
        ) : null}
      </div>
    </Shell>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return (
    <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">{children}</p>
  );
}

function Shell({
  code,
  error,
  displayName = null,
  children,
}: {
  code: string;
  error?: string;
  displayName?: string | null;
  children: React.ReactNode;
}) {
  return (
    <>
      <Sidebar displayName={displayName} />
      <div className="flex flex-1 flex-col lg:ml-64">
        <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-6 py-14">
          <header className="flex flex-col gap-2">
            <Label>Join code</Label>
            <h1 className="font-mono text-5xl font-semibold tracking-[0.16em] text-fg">{code}</h1>
          </header>

          {error ? (
            <p
              role="alert"
              className="rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
            >
              {error}
            </p>
          ) : null}

          {children}
        </main>
      </div>
    </>
  );
}

function HomeLink() {
  return (
    <Link
      href="/"
      className="text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
    >
      Back home
    </Link>
  );
}
