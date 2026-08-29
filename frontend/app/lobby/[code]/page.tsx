import Link from "next/link";
import { redirect } from "next/navigation";

import { ButtonLink } from "@/components/ui/Button";
import { LobbyRealtime } from "@/components/lobby/LobbyRealtime";
import { LobbyLineup } from "@/components/lobby/LobbyLineup";
import { LobbyTopStrip } from "@/components/lobby/LobbyTopStrip";
import { GameSelector } from "@/components/lobby/GameSelector";
import { LobbyScoreboard } from "@/components/lobby/LobbyScoreboard";
import { LobbyActivity } from "@/components/lobby/LobbyActivity";
import { AutoJoinRoom } from "@/components/lobby/AutoJoinRoom";
import { createClient } from "@/lib/supabase/server";
import { GuestJoin } from "@/components/auth/GuestJoin";
import { isGuestViewer, isSignedInViewer } from "@/lib/auth/viewer";
import { guestSessionFinishedHref } from "@/lib/auth/guest-lifecycle";
import { fetchLobbyWins } from "@/lib/lobbies/scoreboard";
import { fetchLobbyActivity } from "@/lib/lobbies/activity";
import { fetchLobbyMemberStats } from "@/lib/lobbies/player-stats";
import type { MatchGame } from "@/lib/games/catalog";

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

  // The sidebar shows who you are on every screen, so the viewer's own name is
  // needed here whether or not they turn out to be in this room.
  const { data: viewer } = await supabase
    .from("profiles")
    .select("display_name, avatar_url")
    .eq("id", claims.sub)
    .single();
  const displayName = viewer?.display_name ?? (claims.email as string | undefined) ?? null;
  const avatarUrl = viewer?.avatar_url ?? null;
  const email = (claims.email as string | undefined) ?? null;

  // RLS returns nothing for a room you are not a member of, so maybeSingle()
  // rather than single() — "no row" is a normal state here, not a failure. It
  // also means we cannot tell a bad code from a room we haven't joined, which
  // is why both fall through to the join prompt and let the RPC decide.
  const { data: lobby } = await supabase
    .from("lobbies")
    .select(
      "id, code, host_id, closed_at, selected_game, lobby_members(user_id, joined_at, last_seen_at, left_at, profiles(display_name, avatar_url, is_guest))",
    )
    .eq("code", code)
    .maybeSingle();

  if (!lobby) {
    return (
      <Shell code={code} error={errorText} displayName={displayName} email={email} avatarUrl={avatarUrl}>
        <AutoJoinRoom code={code} />
      </Shell>
    );
  }

  if (lobby.closed_at) {
    if (isGuestViewer(claims)) redirect(guestSessionFinishedHref("/"));
    return (
      <Shell code={code} error={errorText} displayName={displayName} email={email} avatarUrl={avatarUrl}>
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
    live?.matches.find(
      (m) => m.status === "setup" || m.status === "playing" || m.status === "paused",
    ) ?? null;
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
  const [wins, activity, memberStats] = await Promise.all([
    fetchLobbyWins(supabase, lobby.id),
    fetchLobbyActivity(supabase, lobby.id),
    fetchLobbyMemberStats(supabase, lobby.id),
  ]);

  return (
    <Shell code={code} error={errorText} displayName={displayName} email={email} avatarUrl={avatarUrl} lobbyId={lobby.id} isHost={isHost}>
      <LobbyRealtime lobbyId={lobby.id} />

      {inFlight ? (
        <p className="rounded bg-surface-raised px-3.5 py-2.5 text-sm text-fg-muted shadow-well">
          A game is in progress. You&apos;re in for the next one.
        </p>
      ) : null}

      {/* Three regions, CoD-lobby-style: room activity on the left, the roster
          in the middle, room actions on the right — not two columns with a
          second block stacked under the roster, which read as "content at
          the bottom" rather than "content on the left." Source order stays
          roster-first for mobile; `lg:order-*` only reshuffles it once
          there's room for three columns side by side. */}
      <div className="grid gap-6 lg:grid-cols-[minmax(6rem,0.4fr)_minmax(0,2.4fr)_minmax(20rem,1fr)] lg:items-start lg:gap-10">
        <div className="lg:order-2">
          <LobbyLineup members={members} hostId={lobby.host_id} viewerId={claims.sub} stats={Object.fromEntries(memberStats)} />
        </div>

        <div className="lg:order-1 lg:sticky lg:top-14">
          <LobbyActivity activity={activity} />
        </div>

        <aside className="flex flex-col gap-8 lg:order-3 lg:sticky lg:top-14">
          <GameSelector
            lobbyId={lobby.id}
            code={code}
            isHost={isHost}
            inFlight={Boolean(inFlight)}
            selectedGame={lobby.selected_game as MatchGame | null}
            players={members.length}
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

          <LobbyScoreboard members={members} wins={Object.fromEntries(wins)} />
        </aside>
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
  email = null,
  avatarUrl = null,
  lobbyId = null,
  isHost = false,
  children,
}: {
  code: string;
  error?: string;
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  lobbyId?: string | null;
  isHost?: boolean;
  children: React.ReactNode;
}) {
  return (
    <main className="flex w-full flex-1 flex-col px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20">
      <LobbyTopStrip lobbyId={lobbyId} code={code} isHost={isHost} displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <div className="flex flex-1 flex-col gap-6 pt-4 pb-12 sm:pt-6 lg:gap-8 lg:pt-8">
        {/* Once a real room exists, LobbyTopStrip's InviteSuite carries the
            code instead — always in reach there, rather than a heading that
            scrolls away with the roster. This plain heading stays visible
            only for the states before that: signed out, no room found yet,
            or closed — screens where there's no invite to make. It still
            renders (just off-screen) once a room exists, so the page keeps
            exactly one <h1> either way. */}
        {!lobbyId ? (
          <header className="flex flex-col gap-2">
            <Label>Join code</Label>
            <h1 className="font-mono text-[34px] leading-none font-semibold tracking-[0.16em] text-fg sm:text-[40px]">
              {code}
            </h1>
          </header>
        ) : (
          <h1 className="sr-only">Room {code}</h1>
        )}

        {error ? (
          <p
            role="alert"
            className="rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
          >
            {error}
          </p>
        ) : null}

        {children}
      </div>
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
