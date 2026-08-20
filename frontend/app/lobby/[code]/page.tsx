import Link from "next/link";
import { redirect } from "next/navigation";

import { TopBar } from "@/components/layout/TopBar";
import { Button, ButtonLink } from "@/components/ui/Button";
import { LobbyRealtime } from "@/components/lobby/LobbyRealtime";
import { LobbyLineup } from "@/components/lobby/LobbyLineup";
import { AutoJoinRoom } from "@/components/lobby/AutoJoinRoom";
import { claimLobbyHost, closeLobby, leaveLobby } from "@/lib/lobbies/actions";
import { createClient } from "@/lib/supabase/server";
import { GuestJoin } from "@/components/auth/GuestJoin";
import { canCreateLobby, isGuestViewer, isSignedInViewer } from "@/lib/auth/viewer";
import { guestSessionFinishedHref } from "@/lib/auth/guest-lifecycle";

export default async function LobbyPage(props: PageProps<"/lobby/[code]">) {
  const { code: rawCode } = await props.params;
  const code = rawCode.trim().toUpperCase();

  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  if (!isSignedInViewer(claims)) {
    return (
      <Shell code={code} error={errorText}>
        <p className="text-sm leading-6 text-fg-muted">You&apos;ve been invited to this room. Join in with a name, or sign in to an account.</p>
        <GuestJoin code={code} />
        <ButtonLink href={`/login?next=${encodeURIComponent(`/lobby/${code}`)}`} variant="ghost">Sign in instead</ButtonLink>
      </Shell>
    );
  }

  // The top bar shows who you are on every screen, so the viewer's own name is
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
      "id, code, host_id, closed_at, lobby_members(user_id, joined_at, last_seen_at, left_at, profiles(display_name, is_guest))",
    )
    .eq("code", code)
    .maybeSingle();

  if (!lobby) {
    return (
      <Shell code={code} error={errorText} displayName={displayName}>
        <AutoJoinRoom code={code} />
      </Shell>
    );
  }

  if (lobby.closed_at) {
    if (isGuestViewer(claims)) redirect(guestSessionFinishedHref("/"));
    return (
      <Shell code={code} error={errorText} displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">This room has closed.</p>
        <HomeLink />
      </Shell>
    );
  }

  // The room is a waiting area while nothing is running in it. Once a run
  // starts, the people it snapshotted follow it into the match — the host by
  // their own redirect, everybody else because LobbyRealtime refreshed this
  // page and the run is now here.
  //
  // Only the people it snapshotted. Somebody who walked in after the roster was
  // frozen is not in this game, so sending them to the match screen would put
  // them in front of a board they cannot act on. They wait here and are in for
  // the next one, which is what the two-roster split in 0003 was for.
  const { data: live } = await supabase
    .from("runs")
    .select("id, matches(id, status), run_participants(user_id)")
    .eq("lobby_id", lobby.id)
    .eq("status", "active")
    .maybeSingle();

  const inFlight =
    live?.matches.find((m) => m.status === "setup" || m.status === "playing") ?? null;
  const seated = live?.run_participants.some((p) => p.user_id === claims.sub) ?? false;

  if (inFlight && seated) redirect(`/match/${inFlight.id}`);

  const members = lobby.lobby_members
    .filter((m) => m.left_at === null)
    .sort((a, b) => a.joined_at.localeCompare(b.joined_at));

  const isHost = lobby.host_id === claims.sub;
  // Only the host is offered a format, so only the host's page pays for the
  // bounds behind it. A failure here is not fatal: the picker disappears and
  // the dealer falls back to the whole pool.
  const [{ data: era }, { data: higherOrLowerEra }] = isHost
    ? await Promise.all([
      supabase.schema("auction").rpc("season_bounds"),
      supabase.schema("higher_or_lower").rpc("season_bounds" as never) as unknown as Promise<{ data: { season_min: number; season_max: number } | null }>,
    ])
    : [{ data: null }, { data: null }];
  const { data: activeHost } = await supabase.rpc("lobby_host_is_active", { p_lobby_id: lobby.id });
  const hostIsActive = activeHost ?? true;
  const canTakeHostControls = !isHost && !hostIsActive && canCreateLobby(claims);
  return (
    <Shell code={code} error={errorText} displayName={displayName}>
      <LobbyRealtime lobbyId={lobby.id} />

      {inFlight ? (
        <p className="rounded border border-line bg-surface-raised px-3.5 py-2.5 text-sm text-fg-muted">
          A game is in progress. You&apos;re in for the next one.
        </p>
      ) : null}

      <LobbyLineup
        lobbyId={lobby.id}
        code={code}
        members={members}
        hostId={lobby.host_id}
        viewerId={claims.sub}
        isHost={isHost}
        inFlight={Boolean(inFlight)}
        hostIsActive={hostIsActive}
        era={
          era?.season_min != null && era.season_max != null && era.min_span != null
            ? { seasonMin: era.season_min, seasonMax: era.season_max, minSpan: era.min_span }
            : null
        }
        higherOrLowerEra={
          higherOrLowerEra?.season_min != null && higherOrLowerEra.season_max != null
            ? { seasonMin: higherOrLowerEra.season_min, seasonMax: higherOrLowerEra.season_max }
            : null
        }
      />

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

        {canTakeHostControls ? (
          <form action={claimLobbyHost}>
            <input type="hidden" name="lobby_id" value={lobby.id} />
            <input type="hidden" name="code" value={code} />
            <Button type="submit" variant="ghost">
              Take host controls
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
      <TopBar displayName={displayName} />
      <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-6 px-4 py-10 pb-16 sm:px-6 sm:py-12 lg:gap-8 lg:px-8 lg:py-14 lg:pb-20">
        <header className="flex flex-col gap-2">
          <Label>Join code</Label>
          <h1 className="font-mono text-[34px] leading-none font-semibold tracking-[0.16em] text-fg sm:text-[40px]">
            {code}
          </h1>
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
