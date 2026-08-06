import Link from "next/link";
import { redirect } from "next/navigation";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { CardBack } from "@/components/ui/CardBack";
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
  if (!claims) redirect("/login");

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

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
      <Shell code={code} error={errorText}>
        <p className="text-sm leading-6 text-fg-muted">You&apos;re not in this room yet.</p>
        <form action={joinLobby}>
          <input type="hidden" name="code" value={code} />
          <Button type="submit">Take a seat</Button>
        </form>
        <HomeLink />
      </Shell>
    );
  }

  if (lobby.closed_at) {
    return (
      <Shell code={code} error={errorText}>
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
    <Shell code={code} error={errorText}>
      <LobbyRealtime lobbyId={lobby.id} />

      <Label>
        {members.length} / {CAPACITY} at the table
      </Label>

      {/* Players who've arrived are face up. Empty seats are cards still in the
          pack — same rule as everywhere else: red means not yet revealed. */}
      <ul className="flex flex-col gap-2.5">
        {members.map((m) => (
          <li key={m.user_id}>
            <Card>
              <div className="flex items-baseline justify-between gap-3 px-3 pt-2.5 pb-3">
                <span className="font-slab text-xl leading-none -skew-x-7 uppercase">
                  {m.profiles?.display_name ?? "Unknown player"}
                </span>
                <span className="font-mono text-[10px] tracking-[0.13em] text-pencil uppercase">
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
            <CardBack label="Empty seat, still in the pack" className="flex h-[52px] items-center">
              <span className="relative w-full text-center font-mono text-[10px] tracking-[0.15em] text-stock/85 uppercase">
                Still in the pack
              </span>
            </CardBack>
          </li>
        ))}
      </ul>

      <div className="mt-2 flex flex-col gap-2.5">
        <form action={leaveLobby}>
          <input type="hidden" name="lobby_id" value={lobby.id} />
          <Button type="submit" variant="ghost">
            Leave the table
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
              Close the table for everyone
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
  children,
}: {
  code: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-6 px-6 py-16">
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
