import Link from "next/link";
import { redirect } from "next/navigation";
/* eslint-disable @typescript-eslint/no-explicit-any -- Supabase types are regenerated after migration 0057 lands. */

import { AuctionMatch } from "@/components/games/auction/AuctionMatch";
import { MatchSetup } from "@/components/games/auction/MatchSetup";
import { HigherOrLowerMatch } from "@/components/games/higher-or-lower/HigherOrLowerMatch";
import { QbSeasonBuilderMatch } from "@/components/games/qb-season-builder/QbSeasonBuilderMatch";
import { SabotageDraftMatch } from "@/components/games/sabotage-draft/SabotageDraftMatch";
import { WavelengthMatch } from "@/components/games/wavelength/WavelengthMatch";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import type { AuctionFormat, Player, Turn } from "@/lib/games/auction/board";
import type { Board } from "@/lib/games/higher-or-lower/board";
import { QbSeasonBuilderResult } from "@/components/games/qb-season-builder/QbSeasonBuilderResult";
import { boardFromRow } from "@/lib/games/qb-season-builder/board";
import { boardFromState as wavelengthBoardFromState } from "@/lib/games/wavelength/board";
import { fetchPersonalBest, fetchResult } from "@/lib/games/qb-season-builder/read";
import { playSolo } from "@/lib/platform/lobbies/actions";
import { createClient } from "@/lib/supabase/server";
import { chromeIdentity, isGuestViewer, isSignedInViewer } from "@/lib/foundation/identity/viewer";

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
  const { error } = await props.searchParams;
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!isSignedInViewer(claims)) {
    redirect(`/login?next=${encodeURIComponent(`/match/${id}`)}`);
  }

  const { data: viewer } = await supabase
    .from("profiles")
    .select("display_name, avatar_url")
    .eq("id", claims.sub)
    .single();
  const { displayName, email, avatarUrl } = chromeIdentity(claims, viewer);

  // RLS returns nothing for a match you are not in, so "no row" is a normal
  // state here rather than a failure.
  const { data: match } = await supabase
    .from("matches")
    .select("id, game, status, run_id, runs(lobby_id, lobbies(code, host_id))")
    .eq("id", id)
    .maybeSingle();

  if (!match) {
    return (
      <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
        <p className="text-sm leading-6 text-fg-muted">
          This game isn&apos;t yours, or it no longer exists.
        </p>
        <HomeLink />
      </Shell>
    );
  }

  const code = match.runs?.lobbies?.code ?? null;
  const isHost = match.runs?.lobbies?.host_id === claims.sub;

  // A replay can race with a second submit. Keep the server's one-time-choice
  // refusal visible instead of immediately following the winner's action.
  if (error) {
    return (
      <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
        <p role="alert" className="text-sm leading-6 text-fg-muted">{error}</p>
        {code ? <BackToRoom code={code} /> : <HomeLink />}
      </Shell>
    );
  }

  // A tab opened after the host has already made the choice still reaches the
  // shared destination; Realtime below is only the fast path for open tabs.
  const { data: postGameAction } = match.status === "complete"
    ? await supabase
      .from("post_game_actions")
      .select("choice, next_match_id")
      .eq("match_id", id)
      .maybeSingle()
    : { data: null };
  if (postGameAction) {
    const destination = postGameAction.choice === "replay" && postGameAction.next_match_id
      ? `/match/${postGameAction.next_match_id}`
      : code ? `/lobby/${code}` : "/";
    redirect(destination);
  }

  // The seam start_run leaves open: the run exists and the game has not dealt
  // yet. Normally a blink. If it sticks, the janitor abandons the match.
  if (match.status === "setup") {
    return (
      <Shell displayName={displayName} email={email} avatarUrl={avatarUrl} sidebar={false}>
        <MatchSetup matchId={match.id} />
      </Shell>
    );
  }

  if (match.status === "abandoned") {
    return (
      <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
        <p className="text-sm leading-6 text-fg-muted">This game was abandoned.</p>
        {code ? <BackToRoom code={code} /> : <HomeLink />}
      </Shell>
    );
  }

  // Each game reads its own tables out of its own schema, so this is where one
  // match screen becomes two. The shell above — who you are, whether the match
  // is yours, whether it has been dealt or abandoned — is the platform's and is
  // the same for every game.
  if (match.game === "sabotage_draft") {
    const sabotage = supabase as any;
    const [stateResult, playersResult, spinsResult, picksResult, statusesResult, hitsResult, guessesResult, passesResult, decisionsResult, standingsResult, tiebreaksResult, avResult] = await Promise.all([
      sabotage.schema("sabotage_draft").rpc("state", { p_match_id: id }),
      sabotage.from("sabotage_draft_players").select("*, profiles(display_name, avatar_url)").eq("match_id", id).order("seat"),
      sabotage.from("sabotage_draft_round_spins").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_picks").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_pick_statuses").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_pick_hits").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_guesses").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_passes").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_x_factor_decisions").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_standings").select("*").eq("match_id", id),
      sabotage.from("sabotage_draft_tiebreak_games").select("*").eq("match_id", id),
      sabotage.schema("sabotage_draft").rpc("pick_avs", { p_match_id: id }),
    ]);
    const row = stateResult.data;
    if (!row || row.round_count == null || row.current_round == null || !row.slot || !row.server_now) {
      return <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}><p className="text-sm leading-6 text-fg-muted">This game is no longer available.</p><HomeLink /></Shell>;
    }
    return <SabotageDraftMatch matchId={id} viewerId={claims.sub} roomCode={code} isHost={isHost} paused={match.status === "paused"} initial={{
      board: row,
      players: (playersResult.data ?? []).map(({ profiles, ...player }: any) => ({ ...player, display_name: profiles?.display_name ?? "Unknown player", avatar_url: profiles?.avatar_url ?? null })),
      spins: spinsResult.data ?? [],
      picks: picksResult.data ?? [], statuses: statusesResult.data ?? [], hits: hitsResult.data ?? [], guesses: guessesResult.data ?? [], passes: passesResult.data ?? [],
      decisions: decisionsResult.data ?? [], standings: standingsResult.data ?? [], tiebreaks: tiebreaksResult.data ?? [], pickAvs: avResult.data ?? [],
    }} />;
  }

  if (match.game === "wavelength_2v2") {
    // Do not fetch wavelength_targets: that table is psychic-only, and a
    // match screen must never receive hidden state merely to conceal it later.
    const wavelength = supabase as any;
    const [stateResult, playersResult, roundsResult, cardsResult, cluesResult, statusesResult, resultResult] = await Promise.all([
      wavelength.schema("wavelength").rpc("state", { p_match_id: id }),
      wavelength.from("wavelength_players").select("*, profiles(display_name, avatar_url)").eq("match_id", id).order("seat"),
      wavelength.from("wavelength_rounds").select("*").eq("match_id", id).order("round"),
      wavelength.from("wavelength_cards").select("*").eq("match_id", id).order("round"),
      wavelength.from("wavelength_clues").select("*").eq("match_id", id).order("round"),
      wavelength.from("wavelength_clue_statuses").select("*").eq("match_id", id),
      wavelength.from("wavelength_results").select("*").eq("match_id", id).maybeSingle(),
    ]);
    const board = wavelengthBoardFromState(stateResult.data);
    if (!board) {
      return <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}><p className="text-sm leading-6 text-fg-muted">This game is no longer available.</p><HomeLink /></Shell>;
    }
    return <WavelengthMatch matchId={id} viewerId={claims.sub} roomCode={code} isHost={isHost} paused={match.status === "paused"} initial={{
      board,
      players: (playersResult.data ?? []).map(({ profiles, ...player }: any) => ({ ...player, display_name: profiles?.display_name ?? "Unknown player", avatar_url: profiles?.avatar_url ?? null })),
      rounds: roundsResult.data ?? [], cards: cardsResult.data ?? [], clues: cluesResult.data ?? [], clueStatuses: statusesResult.data ?? [], result: resultResult.data ?? null,
    }} />;
  }

  if (match.game === "higher_or_lower") {
    const [boardResult, cardsResult, seatsResult, callsResult, statusesResult, standingsResult, statsResult] = await Promise.all([
      supabase.schema("higher_or_lower").rpc("state", { p_match_id: id }),
      supabase.from("higher_or_lower_cards").select("*").eq("match_id", id).order("ordinal"),
      supabase
        .from("higher_or_lower_players")
        // The compound (match_id, user_id) FKs on higher_or_lower_calls and
        // higher_or_lower_call_statuses give PostgREST a second, many-to-many
        // path to profiles alongside this table's direct one — an unqualified
        // `profiles(...)` embed is ambiguous between them (PGRST201). Naming
        // the direct FK is how every other embed in this file stays a single
        // choice.
        .select("*, profiles!higher_or_lower_players_user_id_fkey(display_name, avatar_url)")
        .eq("match_id", id)
        .order("seat"),
      supabase.from("higher_or_lower_calls").select("*").eq("match_id", id).order("created_at"),
      supabase.from("higher_or_lower_call_statuses").select("*").eq("match_id", id),
      supabase.from("match_players").select("*").eq("match_id", id),
      supabase.from("higher_or_lower_player_stats").select("all_time_high").eq("user_id", claims.sub).maybeSingle(),
    ]);

    const row = boardResult.data;
    if (
      !row || row.question_count === null || row.current_question === null ||
      row.scoring_mode === null || row.season_from === null || row.season_to === null ||
      row.phase === null || row.server_now === null
    ) {
      return (
        <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
          <p className="text-sm leading-6 text-fg-muted">This game is no longer available.</p>
          <HomeLink />
        </Shell>
      );
    }

    const matchScreen = (
      <HigherOrLowerMatch
        matchId={id}
        viewerId={claims.sub}
        roomCode={code}
        isHost={isHost}
        paused={match.status === "paused"}
        initial={{
          board: {
            questionCount: row.question_count,
            currentQuestion: row.current_question,
            scoringMode: row.scoring_mode,
            seasonFrom: row.season_from,
            seasonTo: row.season_to,
            phase: row.phase as Board["phase"],
            phaseDeadline: row.phase_deadline,
            serverNow: row.server_now,
          },
          cards: cardsResult.data ?? [],
          players: (seatsResult.data ?? []).map(({ profiles, ...seat }) => ({
            ...seat,
            display_name: profiles?.display_name ?? "Unknown player",
            avatar_url: profiles?.avatar_url ?? null,
          })),
          calls: callsResult.data ?? [],
          statuses: statusesResult.data ?? [],
          standings: standingsResult.data ?? [],
          allTimeHigh: statsResult.data?.all_time_high ?? 0,
        }}
      />
    );

    // Solo is a personal challenge, not a room that needs the full-bleed
    // match-table treatment. Keep party games immersive, but put a solo run
    // back inside the application surface the player navigated from.
    return code === null ? (
      <SoloMatchShell displayName={displayName} email={email} avatarUrl={avatarUrl}>
        {matchScreen}
      </SoloMatchShell>
    ) : matchScreen;
  }

  // A solo run only: it has no room, so it takes the solo shell. It is the same
  // read for a fresh start, a reload and a run reopened by its URL — the server
  // keeps the spin and the picks, so "resume" is just this fetch.
  if (match.game === "qb_season_builder") {
    const { data: row } = await supabase.schema("qb_season_builder").rpc("state", { p_match_id: id });
    const board = boardFromRow(row);
    if (!board) {
      return (
        <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
          <p className="text-sm leading-6 text-fg-muted">This game is no longer available.</p>
          <HomeLink />
        </Shell>
      );
    }

    // A finished run is its reveal. The board's `shown` is the player's own —
    // every option they were dealt, values included — so it comes from here and
    // not from the public result, which does not carry it.
    if (board.phase === "complete") {
      const result = await fetchResult(supabase, id);
      if (result) {
        const personalBest = await fetchPersonalBest(supabase, claims, result.mode);
        return (
          <SoloMatchShell displayName={displayName} email={email} avatarUrl={avatarUrl}>
            <QbSeasonBuilderResult
              result={result}
              shown={board.shown}
              personalBest={personalBest}
              isGuest={isGuestViewer(claims)}
              staged
              startNewSeason={playSolo}
            />
          </SoloMatchShell>
        );
      }
    }

    return (
      <SoloMatchShell displayName={displayName} email={email} avatarUrl={avatarUrl}>
        <QbSeasonBuilderMatch matchId={id} initial={board} isGuest={isGuestViewer(claims)} startNewSeason={playSolo} />
      </SoloMatchShell>
    );
  }

  const [turnResult, lotsResult, seatsResult, bidsResult, standingsResult, formatResult, eraResult, scoutHintsResult, sealedBidsResult, sealedStatusesResult] = await Promise.all([
    supabase.schema("auction").rpc("state", { p_match_id: id }),
    supabase.from("auction_lots").select("*").eq("match_id", id).order("seq"),
    supabase
      .from("auction_players")
      .select("*, profiles(display_name, avatar_url)")
      .eq("match_id", id)
      .order("seat"),
    supabase.from("auction_bids").select("*").eq("match_id", id).order("bid_seq"),
    supabase.from("match_players").select("*").eq("match_id", id),
    supabase
      .from("auction_matches")
      .select("scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, season_from, season_to, token_count")
      .eq("match_id", id)
      .maybeSingle(),
    isHost ? supabase.schema("auction").rpc("season_bounds") : Promise.resolve({ data: null }),
    // RLS scopes this to the viewer's own rows -- see ScoutHint's doc comment.
    supabase.from("auction_scouting_hints").select("*").eq("match_id", id),
    // Also viewer-own only -- see SealedBid's doc comment.
    supabase.from("auction_sealed_bids").select("*").eq("match_id", id),
    // Presence, readable for every match member -- see SealedBidStatus.
    supabase.from("auction_sealed_bid_statuses").select("*").eq("match_id", id),
  ]);

  const state = turnResult.data;
  if (!state) {
    return (
      <Shell displayName={displayName} email={email} avatarUrl={avatarUrl}>
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
    freeFallbackSeat: state.free_fallback_seat ?? null,
    stuckSeat: state.stuck_seat ?? null,
    turnDeadline: state.turn_deadline,
    phase: (state.phase ?? "lot_preview") as Turn["phase"],
    phaseDeadline: state.phase_deadline,
  };

  const players: Player[] = (seatsResult.data ?? []).map(({ profiles, ...seat }) => ({
    ...seat,
    display_name: profiles?.display_name ?? "Unknown player",
    avatar_url: profiles?.avatar_url ?? null,
  }));
  const format = auctionFormat(formatResult.data);

  return (
    <AuctionMatch
        matchId={id}
        viewerId={claims.sub}
        roomCode={code}
        isHost={isHost}
        paused={match.status === "paused"}
        complete={match.status === "complete"}
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
        scoutHints: scoutHintsResult.data ?? [],
        sealedBids: sealedBidsResult.data ?? [],
        sealedStatuses: sealedStatusesResult.data ?? [],
        format,
        era: eraResult.data?.season_min != null && eraResult.data.season_max != null && eraResult.data.min_span != null
          ? { seasonMin: eraResult.data.season_min, seasonMax: eraResult.data.season_max, minSpan: eraResult.data.min_span }
          : null,
        }}
    />
  );
}

function auctionFormat(row: {
  scoring_mode: string | null;
  roster_preset: string | null;
  qb_slots: number | null;
  rb_slots: number | null;
  wr_slots: number | null;
  te_slots: number | null;
  flex_slots: number | null;
  purse: number | null;
  season_from: number | null;
  season_to: number | null;
  // Not part of the null-guard below: unlike the other format columns, this
  // one has a hard NOT NULL DEFAULT and exists on every match row, including
  // ones dealt before this column existed.
  token_count: number;
} | null): AuctionFormat | null {
  if (
    !row ||
    row.scoring_mode === null || row.roster_preset === null || row.qb_slots === null ||
    row.rb_slots === null || row.wr_slots === null || row.te_slots === null ||
    row.flex_slots === null || row.purse === null ||
    row.season_from === null || row.season_to === null
  ) return null;
  return {
    scoringMode: row.scoring_mode,
    rosterPreset: row.roster_preset,
    qbSlots: row.qb_slots,
    rbSlots: row.rb_slots,
    wrSlots: row.wr_slots,
    teSlots: row.te_slots,
    flexSlots: row.flex_slots,
    purse: row.purse,
    seasonFrom: row.season_from,
    seasonTo: row.season_to,
    tokenCount: row.token_count,
  };
}

function Shell({
  displayName,
  email = null,
  avatarUrl = null,
  sidebar = true,
  children,
}: {
  displayName: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  /** A match that is about to be played is a game screen, not a dashboard page. */
  sidebar?: boolean;
  children: React.ReactNode;
}) {
  return (
    <>
      {sidebar && <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />}
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-5 px-6 py-14">
        {children}
      </main>
    </>
  );
}

/** The normal product chrome for a solo run. Kept separate from `Shell`: the
 * latter is intentionally a narrow recovery/setup surface, while this child
 * owns a full dashboard workspace. */
function SoloMatchShell({
  displayName,
  email,
  avatarUrl,
  children,
}: {
  displayName: string | null;
  email: string | null;
  avatarUrl: string | null;
  children: React.ReactNode;
}) {
  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      {children}
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
