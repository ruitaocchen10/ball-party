import Link from "next/link";
import { redirect } from "next/navigation";

import { AuctionMatch } from "@/components/auction/AuctionMatch";
import { MatchSetup } from "@/components/auction/MatchSetup";
import { TopBar } from "@/components/layout/TopBar";
import type { Player, Turn } from "@/lib/auction/board";
import { createClient } from "@/lib/supabase/server";

/**
 * The match screen.
 *
 * Not nested under /lobby/[code], because a match outlives the URL you started
 * it from and the room code is not part of its identity.
 *
 * This renders once, on the server, and then gets out of the way: everything
 * after the first paint arrives over Realtime and is applied to client state
 * directly. A router.refresh() per bid inside a ten-second turn is exactly the
 * latency this whole design avoids, which is why the lobby's strategy is not
 * reused here.
 *
 * Reconnect is a reload. There is no special path — the state below is fetched
 * again, the subscription re-establishes, and auto-pass already made being away
 * survivable.
 */
export default async function MatchPage(props: PageProps<"/match/[id]">) {
  const { id } = await props.params;
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims || claims.is_anonymous === true) {
    redirect(`/login?next=${encodeURIComponent(`/match/${id}`)}`);
  }

  const { data: viewer } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", claims.sub)
    .single();
  const displayName = viewer?.display_name ?? (claims.email as string | undefined) ?? null;

  // RLS returns nothing for a match you are not in, so "no row" is a normal
  // state here rather than a failure.
  const { data: match } = await supabase
    .from("matches")
    .select("id, status, run_id, runs(lobby_id, lobbies(code))")
    .eq("id", id)
    .maybeSingle();

  if (!match) {
    return (
      <Shell displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">
          This game isn&apos;t yours, or it no longer exists.
        </p>
        <HomeLink />
      </Shell>
    );
  }

  const code = match.runs?.lobbies?.code ?? null;

  // The seam start_run leaves open: the run exists and the game has not dealt
  // yet. Normally a blink. If it sticks, the janitor abandons the match.
  if (match.status === "setup") {
    return (
      <Shell displayName={displayName}>
        <MatchSetup matchId={match.id} />
      </Shell>
    );
  }

  if (match.status === "abandoned") {
    return (
      <Shell displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">This game was abandoned.</p>
        {code ? <BackToRoom code={code} /> : <HomeLink />}
      </Shell>
    );
  }

  const [turnResult, lotsResult, seatsResult, bidsResult, standingsResult] = await Promise.all([
    supabase.rpc("auction_state", { p_match_id: id }),
    supabase.from("auction_lots").select("*").eq("match_id", id).order("seq"),
    supabase
      .from("auction_players")
      .select("*, profiles(display_name)")
      .eq("match_id", id)
      .order("seat"),
    supabase.from("auction_bids").select("*").eq("match_id", id).order("bid_seq"),
    supabase.from("match_players").select("*").eq("match_id", id),
  ]);

  const state = turnResult.data;
  if (!state) {
    return (
      <Shell displayName={displayName}>
        <p className="text-sm leading-6 text-fg-muted">This game is no longer available.</p>
        <HomeLink />
      </Shell>
    );
  }

  const turn: Turn = {
    lotCount: state.lot_count ?? 0,
    currentLot: state.current_lot ?? 1,
    turnSeat: state.turn_seat,
    openerSeat: state.opener_seat ?? 0,
    turnDeadline: state.turn_deadline,
    phase: (state.phase ?? "lot_preview") as Turn["phase"],
    phaseDeadline: state.phase_deadline,
  };

  const players: Player[] = (seatsResult.data ?? []).map(({ profiles, ...seat }) => ({
    ...seat,
    display_name: profiles?.display_name ?? "Unknown player",
  }));

  return (
    <AuctionMatch
      matchId={id}
      viewerId={claims.sub}
      displayName={displayName}
      roomCode={code}
      initial={{
        turn,
        // The server's clock, so the client can offset its own rather than
        // trust it. A deadline is only a rule if both ends agree what time it
        // is, and only one of them is trustworthy.
        serverNow: state.server_now ?? new Date().toISOString(),
        lots: lotsResult.data ?? [],
        players,
        bids: bidsResult.data ?? [],
        standings: standingsResult.data ?? [],
        complete: match.status === "complete",
      }}
    />
  );
}

function Shell({
  displayName,
  children,
}: {
  displayName: string | null;
  children: React.ReactNode;
}) {
  return (
    <>
      <TopBar displayName={displayName} />
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-5 px-6 py-14">
        {children}
      </main>
    </>
  );
}

function HomeLink() {
  return <Back href="/">Back home</Back>;
}

function BackToRoom({ code }: { code: string }) {
  return <Back href={`/lobby/${code}`}>Back to the room</Back>;
}

function Back({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
    >
      {children}
    </Link>
  );
}
