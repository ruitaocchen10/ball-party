"use client";
/* eslint-disable @typescript-eslint/no-explicit-any -- Supabase types are regenerated after this migration lands. */

import { motion } from "motion/react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type Ref } from "react";
import { createPortal } from "react-dom";

import { FinalStandings, type FinalStandingsRow } from "@/components/runtime/game-runtime/FinalStandings";
import { PauseBanner } from "@/components/runtime/game-runtime/PauseBanner";
import { PauseButton } from "@/components/runtime/game-runtime/PauseButton";
import { PostGameControls } from "@/components/runtime/game-runtime/PostGameControls";
import { PostGameNavigation } from "@/components/runtime/game-runtime/PostGameNavigation";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { SlotReel } from "@/components/foundation/ui-kit/SlotReel";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Card, CardMeta, CardTitle } from "@/components/foundation/ui-kit/Card";
import { Chevron } from "@/components/foundation/ui-kit/Chevron";
import { Concealed } from "@/components/foundation/ui-kit/Concealed";
import { abbreviate, MatchStrip, StripCell, StripCellAvatar, StripCellCaption, StripCellMediaBadge, StripCellName, StripCellTextColumn, StripCellTitle } from "@/components/foundation/ui-kit/MatchStrip";
import { HEARTBEAT_MS, TICK_MS, VISIBLE_SLACK_MS, useMatchClock } from "@/lib/runtime/game-runtime/useMatchClock";
import { dropdownUp, springSnappy, tiebreakBoardReveal, tiebreakMatchReveal, tiebreakRoundReveal } from "@/lib/foundation/ui-kit/motion";
import { FRANCHISE_NAMES, franchiseName } from "@/lib/foundation/content/nfl/franchises";
import { gradeForPick, gradeForTeam } from "@/lib/games/sabotage-draft/grades";
import { ROUND_SLOTS, X_FACTOR_ROUND, slotForRound } from "@/lib/games/sabotage-draft/rounds";
import { TURN_REVEAL_MS, useTurnReveal } from "@/lib/games/sabotage-draft/useTurnReveal";
import { createClient } from "@/lib/supabase/client";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";

// One shared clock per turn (see docs/games/sabotage_draft.md): the active
// seat may lock a pick any time within turn_deadline, and every other seat
// may lock in one guess or one pass any time within that same window,
// including before the pick exists. A guess's `result` is therefore nullable
// — pending until the whole turn's action set is complete — and there is no
// longer a separate pick/guess phase to key UI off of, only "is the turn
// open" and "have I already acted."
type Board = { match_id: string; round_count: number; current_round: number; slot: string; turn_deadline: string | null; server_now: string; x_factor_open: boolean; active_user_id: string };
type Player = { match_id: string; user_id: string; seat: number; absent: boolean; display_name: string; avatar_url: string | null };
type Spin = { match_id: string; round_number: number; user_id: string; franchise_code: string };
type Pick = { match_id: string; round_number: number; user_id: string; player_id: string; display_name: string; season: number; by_timeout: boolean; headshot_url: string | null };
type PickStatus = { match_id: string; round_number: number; user_id: string };
type Hit = { match_id: string; round_number: number; target_user_id: string; kind: "respin" | "sabotage" };
type Guess = { match_id: string; round_number: number; user_id: string; target_user_id: string; result: "miss" | "respun" | "sabotaged" | null };
type Pass = { match_id: string; round_number: number; target_user_id: string; user_id: string };
type Option = { player_id: string; display_name: string; season: number; slot_category: string; headshot_url: string | null };
type Decision = { match_id: string; user_id: string; replace_slot: string | null };
type Standing = { user_id: string; roster_strength: number; wins: number; losses: number; tiebreak_rank: number };
type PickAv = { user_id: string; round_number: number; av: number };
// A snapshot of what a turn resolved to, captured once (see the effect in
// SabotageDraftMatch that builds this) the instant the board moves on to the
// next one. `pick` is only ever populated when the turn was the viewer's own
// -- sabotage_draft_picks' RLS (user_id = auth.uid()) means a pick's identity
// never reaches anyone else's client at all, resolved or not, so a viewer
// watching someone else's turn resolve gets `spin`/`slot` instead: the same
// franchise-and-slot, name-withheld shape RosterBoard's own concealed rows
// already show for a still-open pick.
type TurnResultData = { round: number; userId: string; playerName: string; mine: boolean; pick: Pick | null; spin: Spin | null; slot: string; outcome: "kept" | "respun" | "sabotaged"; actorName: string | null };
type Tiebreak = { record_wins: number; bracket_round: number; game_number: number; player_a: string; player_b: string | null; winner_user_id: string; player_a_score: number | null; player_b_score: number | null };

const MESSAGE: Record<string, string> = { already_picked: "Your pick is already locked.", already_acted: "You have already guessed or passed on this turn.", turn_closed: "This turn has closed.", invalid_pick: "Choose a player from this round's pool.", invalid_guess: "Choose a player from this round's pool.", x_factor_position_mismatch: "Your X-Factor can only replace a slot at the same position.", match_not_playing: "This match isn't accepting moves right now.", not_your_turn: "It isn't your turn right now." };
// The one duration every sabotage draft turn shares -- unlike the auction's
// (which varies by phase), this is set identically in deal_board,
// advance_turn, and submit_x_factor_decision (see
// supabase/migrations/20260826180000_0063_sabotage_draft_merged_turn.sql),
// so TurnClock needs one constant rather than a phase-keyed map.
const TURN_DURATION_MS = 30_000;

export function SabotageDraftMatch({ matchId, viewerId, roomCode = null, isHost = false, paused = false, initial }: { matchId: string; viewerId: string; roomCode?: string | null; isHost?: boolean; paused?: boolean; initial: { board: Board; players: Player[]; spins: Spin[]; picks: Pick[]; statuses: PickStatus[]; hits: Hit[]; guesses: Guess[]; passes: Pass[]; decisions: Decision[]; standings: Standing[]; tiebreaks: Tiebreak[]; pickAvs: PickAv[] } }) {
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);
  const [board, setBoard] = useState(initial.board); const [players, setPlayers] = useState(initial.players); const [spins, setSpins] = useState(initial.spins);
  const [picks, setPicks] = useState(initial.picks); const [statuses, setStatuses] = useState(initial.statuses);
  const [hits, setHits] = useState(initial.hits); const [guesses, setGuesses] = useState(initial.guesses); const [passes, setPasses] = useState(initial.passes);
  const [decisions, setDecisions] = useState(initial.decisions); const [standings, setStandings] = useState(initial.standings); const [tiebreaks, setTiebreaks] = useState(initial.tiebreaks);
  const [pickAvs, setPickAvs] = useState(initial.pickAvs);
  const [options, setOptions] = useState<Option[]>([]); const [error, setError] = useState<string | null>(null); const [pending, setPending] = useState(false);
  const [isPaused, setIsPaused] = useState(paused);
  const stateFrom = (row: Partial<Board>) => row.server_now && row.current_round && row.slot ? setBoard(previous => ({ ...previous, ...row } as Board)) : undefined;
  const refetch = useCallback(async () => {
    const s: any = getClient(); const [state, ps, spinResult, picksResult, statusResult, hitResult, guessResult, passResult, decisionResult, standingResult, tieResult, avResult] = await Promise.all([
      s.schema("sabotage_draft" as never).rpc("state" as never, { p_match_id: matchId } as never), s.from("sabotage_draft_players").select("*, profiles(display_name, avatar_url)").eq("match_id", matchId).order("seat"), s.from("sabotage_draft_round_spins").select("*").eq("match_id", matchId), s.from("sabotage_draft_picks").select("*").eq("match_id", matchId), s.from("sabotage_draft_pick_statuses").select("*").eq("match_id", matchId), s.from("sabotage_draft_pick_hits").select("*").eq("match_id", matchId), s.from("sabotage_draft_guesses").select("*").eq("match_id", matchId), s.from("sabotage_draft_passes").select("*").eq("match_id", matchId), s.from("sabotage_draft_x_factor_decisions").select("*").eq("match_id", matchId), s.from("sabotage_draft_standings").select("*").eq("match_id", matchId), s.from("sabotage_draft_tiebreak_games").select("*").eq("match_id", matchId), s.schema("sabotage_draft" as never).rpc("pick_avs" as never, { p_match_id: matchId } as never),
    ]);
    if (state.data) stateFrom(state.data as Board); if (ps.data) setPlayers(ps.data.map(({ profiles, ...p }: any) => ({ ...p, display_name: profiles?.display_name ?? "Unknown player", avatar_url: profiles?.avatar_url ?? null })));
    if (spinResult.data) setSpins(spinResult.data as Spin[]);
    if (picksResult.data) setPicks(picksResult.data as Pick[]); if (statusResult.data) setStatuses(statusResult.data as PickStatus[]); if (hitResult.data) setHits(hitResult.data as Hit[]); if (guessResult.data) setGuesses(guessResult.data as Guess[]); if (passResult.data) setPasses(passResult.data as Pass[]); if (decisionResult.data) setDecisions(decisionResult.data as Decision[]); if (standingResult.data) setStandings(standingResult.data as Standing[]); if (tieResult.data) setTiebreaks(tieResult.data as Tiebreak[]); if (avResult.data) setPickAvs(avResult.data as PickAv[]);
  }, [getClient, matchId]);
  // Eligible names depend on whose spin they're read against: no target asks
  // for the caller's own (the pick case); a target asks for that player's
  // (the guess case). PickForm uses the bare call below; GuessForm's target
  // is never a choice — it's forced to whoever currently holds the turn — so
  // loadActiveOptions below just pins that argument to board.active_user_id.
  const loadOptions = useCallback(async (targetUserId?: string) => {
    const { data } = await getClient().schema("sabotage_draft" as never).rpc("options" as never, (targetUserId ? { p_match_id: matchId, p_target_user_id: targetUserId } : { p_match_id: matchId }) as never);
    return (data ?? []) as Option[];
  }, [getClient, matchId]);
  useEffect(() => { void loadOptions().then(setOptions); }, [board.current_round, loadOptions]);
  const loadActiveOptions = useCallback(() => loadOptions(board.active_user_id), [loadOptions, board.active_user_id]);
  const deadline = board.turn_deadline;
  const { remainingMs } = useMatchClock({ serverNow: board.server_now, deadline, visibleSlackMs: VISIBLE_SLACK_MS, heartbeatMs: HEARTBEAT_MS, paused: isPaused, expire: () => getClient().schema("sabotage_draft" as never).rpc("tick" as never, { p_match_id: matchId } as never).then(({ data }: any) => data && stateFrom(data)), reconcile: refetch });
  // The browser client is a singleton (see lib/supabase/client.ts), so its
  // Realtime socket and channel cache outlive any one mount of this effect.
  // React Strict Mode's mount->cleanup->mount double-invoke (and any other
  // fast remount) can otherwise race this async setup: a second invocation
  // resumes before the first's cleanup has torn its channel down, `.channel()`
  // hands back that same already-subscribed channel by topic, and `.on()` on
  // it throws. `cancelled` is set synchronously by cleanup -- before any
  // awaited work in a still-running invocation resumes -- so a torn-down
  // invocation always bails before touching the channel at all.
  useEffect(() => { let cancelled = false; let channel: ReturnType<ReturnType<typeof createClient>["channel"]> | undefined; void (async () => { const s = await createRealtimeClient(); if (cancelled) return; const topic = `realtime:sabotage:${matchId}`; const stale = s.realtime.getChannels().find((c: { topic: string }) => c.topic === topic); if (stale) await s.removeChannel(stale); if (cancelled) return; channel = s.channel(`sabotage:${matchId}`).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_matches", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${matchId}` }, (payload: { new: { status?: string } }) => setIsPaused(payload.new.status === "paused")).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_players", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_round_spins", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_picks", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_pick_statuses", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_guesses", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_passes", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_pick_hits", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_x_factor_decisions", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_standings", filter: `match_id=eq.${matchId}` }, () => void refetch()).on("postgres_changes", { event: "*", schema: "public", table: "sabotage_draft_tiebreak_games", filter: `match_id=eq.${matchId}` }, () => void refetch()).subscribe(status => { if (status === "SUBSCRIBED") void refetch(); }); })(); return () => { cancelled = true; if (channel) void getClient().removeChannel(channel); }; }, [matchId, refetch, getClient]);
  const call = async (name: string, args: Record<string, unknown>) => {
    setPending(true);
    setError(null);
    try {
      const { error: rpcError } = await (getClient().schema("sabotage_draft" as never).rpc(name as never, args as never) as any);
      if (rpcError) setError(MESSAGE[rpcError.message] ?? rpcError.message);
      else await refetch();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't save your move. Try again.");
    } finally {
      // Keep the old controls inert until refetch has replaced the stale
      // board snapshot that initiated this move. Otherwise a quick second
      // click can submit the same action again before Realtime catches up.
      setPending(false);
    }
  };
  const myPick = picks.find(p => p.round_number === board.current_round && p.user_id === viewerId); const myDecision = decisions.find(d => d.user_id === viewerId);
  // A guess or a pass is spent per (round, target) now, not once per round
  // flat — the same player gets a fresh shot on every seat's own turn — so
  // "have I already acted this turn" has to be scoped to whoever currently
  // holds the turn, not to the round alone.
  const myGuess = guesses.find(g => g.round_number === board.current_round && g.target_user_id === board.active_user_id && g.user_id === viewerId);
  const myPass = passes.find(p => p.round_number === board.current_round && p.target_user_id === board.active_user_id && p.user_id === viewerId);
  const isActive = viewerId === board.active_user_id;
  const activePlayer = players.find(p => p.user_id === board.active_user_id);
  // One hook drives both the turn panel's reel and whether this turn's own
  // forms are usable yet, so the two can never disagree about which turn is
  // "still spinning" -- see useTurnReveal's own doc comment for why this is
  // also what makes the reel trustworthy regardless of whether any CSS
  // animation actually plays. Called unconditionally, above the standings
  // early-return below, because it's a hook.
  const { revealed: turnRevealed } = useTurnReveal(`${board.current_round}-${board.active_user_id}`);
  // What the *previous* turn resolved to, captured the instant the board
  // moves on -- not on a timer of its own. It rides the same "still
  // spinning" window useTurnReveal already opens for the new turn's reel
  // (see !turnRevealed below): the result stays up for exactly as long as
  // the "Your move" column would otherwise just say "Spinning…", and clears
  // itself the moment that column has real work to show again. `prevTurnRef`
  // starts null on mount for the same reason useTurnReveal's own lastKey
  // does -- a viewer landing mid-turn has no "previous" turn to report on.
  const prevTurnRef = useRef<{ round: number; userId: string } | null>(null);
  const [lastTurnResult, setLastTurnResult] = useState<TurnResultData | null>(null);
  useEffect(() => {
    const prev = prevTurnRef.current;
    prevTurnRef.current = { round: board.current_round, userId: board.active_user_id };
    if (!prev || (prev.round === board.current_round && prev.userId === board.active_user_id)) return;
    const mine = prev.userId === viewerId;
    const pick = mine ? (picks.find(p => p.round_number === prev.round && p.user_id === prev.userId) ?? null) : null;
    const spin = spins.find(s => s.round_number === prev.round && s.user_id === prev.userId) ?? null;
    // A turn that produced nothing to show (mine with no pick row somehow,
    // or someone else's with no spin on record) is skipped rather than
    // rendered empty -- this is a nice-to-have flourish, not something
    // anyone should be blocked by.
    if (mine ? !pick : !spin) return;
    const roundHits = hits.filter(h => h.round_number === prev.round && h.target_user_id === prev.userId);
    const sabotaged = roundHits.some(h => h.kind === "sabotage");
    const respun = !sabotaged && roundHits.some(h => h.kind === "respin");
    const outcome: TurnResultData["outcome"] = sabotaged ? "sabotaged" : respun ? "respun" : "kept";
    const actorGuess = outcome !== "kept" ? guesses.find(g => g.round_number === prev.round && g.target_user_id === prev.userId && g.result === outcome) : undefined;
    setLastTurnResult({
      round: prev.round,
      userId: prev.userId,
      playerName: players.find(p => p.user_id === prev.userId)?.display_name ?? "Someone",
      mine,
      pick,
      spin,
      slot: slotForRound(prev.round),
      outcome,
      actorName: actorGuess ? (players.find(p => p.user_id === actorGuess.user_id)?.display_name ?? null) : null,
    });
  }, [board.current_round, board.active_user_id, picks, spins, hits, guesses, players, viewerId]);
  if (standings.length) return <Final matchId={matchId} roomCode={roomCode} isHost={isHost} viewerId={viewerId} standings={standings} players={players} tiebreaks={tiebreaks} picks={picks} decisions={decisions} pickAvs={pickAvs} />;
  const disabled = pending || isPaused;
  // The turn clock's status label. Computed once here, where isActive and
  // activePlayer already live, rather than inside TurnClock -- it's handed
  // down as a plain string so the component doesn't need to know sabotage
  // draft's own phase shape to render one.
  const turnLabel = isActive
    ? board.turn_deadline ? "Your pick" : board.x_factor_open ? "Your X-Factor" : ""
    : board.turn_deadline ? `Sabotage ${activePlayer?.display_name ?? "…"}` : board.x_factor_open ? `${activePlayer?.display_name ?? "…"}'s X-Factor` : "Locked";
  // Full-bleed, three columns — the same shape and DOM-order reasoning as
  // the auction's own live-play screen (AuctionMatch's main return): what's
  // happening (the turn), what to do about it (your move), then who else is
  // at the table (everyone's teams). Unlike the auction, "what to do about
  // it" isn't always the viewer's own action — most turns it's someone
  // else's, so this column carries whichever of pick/guess/X-Factor
  // actually applies to the viewer right now, and a quiet waiting state
  // otherwise.
  return (
    <main className="mx-auto flex w-full min-h-0 flex-1 flex-col gap-4 overflow-hidden px-4 pt-3 pb-4">
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="flex items-center gap-1.5 font-mono text-xs tracking-[.14em] text-fg-muted uppercase">
          Round {board.current_round} of {board.round_count} · {board.slot.replace("_", " ")}
          <SlotInfo />
        </p>
        {isHost ? <PauseButton matchId={matchId} paused={isPaused} /> : null}
      </header>
      <TurnStrip board={board} players={players} spins={spins} picks={picks} statuses={statuses} hits={hits} viewerId={viewerId} />
      {isPaused ? <PauseBanner /> : null}
      {/* The auction's own ratio (AuctionMatch's grid: .62fr/1fr/.95fr),
          applied directly -- a .15fr nudge toward "Your move" read as too
          subtle to actually feel roomier, so this goes the rest of the way
          rather than guessing at another number in between. */}
      <div className="grid min-h-0 flex-1 gap-4 lg:grid-cols-[minmax(15rem,.62fr)_minmax(20rem,1fr)_minmax(19rem,.95fr)] lg:grid-rows-1">
        <section className="flex min-h-0 flex-col gap-3 lg:col-start-1" aria-label="The turn">
          <TurnSpinner board={board} players={players} spins={spins} revealed={turnRevealed} />
          <TurnClock label={turnLabel} remainingMs={remainingMs} />
        </section>
        <section className="flex min-h-0 flex-col gap-3 lg:col-start-2" aria-label="Your move">
          {pending ? <p role="status" aria-live="polite" className="font-mono text-xs tracking-[0.12em] text-fg-muted uppercase">Saving your move…</p> : null}
          <AnimatedMessage role="alert" className="text-sm text-hidden-text">{error}</AnimatedMessage>
          {board.turn_deadline && !turnRevealed ? (lastTurnResult ? <TurnResultCard result={lastTurnResult} /> : <Card edge={false}><CardTitle>Spinning…</CardTitle><CardMeta>The board is picking {isActive ? "your" : `${activePlayer?.display_name ?? "their"}`} team</CardMeta></Card>) : null}
          {board.turn_deadline && turnRevealed && isActive ? <PickForm options={options} mine={myPick} pending={disabled} onSubmit={(o) => call("submit_pick", { p_match_id: matchId, p_player_id: o.player_id, p_season: o.season })} /> : null}
          {board.turn_deadline && turnRevealed && !isActive ? <GuessForm targetName={activePlayer?.display_name ?? "them"} status={myGuess ? "guessed" : myPass ? "passed" : "open"} pending={disabled} loadOptions={loadActiveOptions} onSubmit={(choice, exact, replacement) => call("submit_guess", { p_match_id: matchId, p_player_id: choice.player_id, p_season: exact ? choice.season : null, p_replacement_player_id: exact ? replacement?.player_id : null, p_replacement_season: exact ? replacement?.season : null })} onPass={() => call("submit_pass", { p_match_id: matchId })} /> : null}
          {board.x_factor_open && isActive ? <Decision mine={myDecision} pending={disabled} replacementSlots={xFactorReplacementSlots(picks.find(p => p.round_number === 14 && p.user_id === viewerId), options)} onSubmit={(slot) => call("submit_x_factor_decision", { p_match_id: matchId, p_replace_slot: slot })} /> : null}
          {board.x_factor_open && !isActive ? <Card edge={false}><CardTitle>{activePlayer?.display_name ?? "…"}&apos;s X-Factor</CardTitle><CardMeta>Waiting on their decision</CardMeta></Card> : null}
          {!board.turn_deadline && !board.x_factor_open ? <Card edge={false}><CardTitle>Between turns</CardTitle><CardMeta>Waiting on the next turn to open</CardMeta></Card> : null}
        </section>
        <aside className="min-h-0 overflow-y-auto lg:col-start-3" aria-label="Everyone's teams">
          <RosterBoard board={board} players={players} spins={spins} picks={picks} statuses={statuses} hits={hits} viewerId={viewerId} justResolved={!turnRevealed ? lastTurnResult : null} />
        </aside>
      </div>
    </main>
  );
}

/** The "?" beside the round header explaining why some slots don't read as fantasy positions. */
function SlotInfo() {
  return (
    <span tabIndex={0} className="group relative inline-flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full border border-fg-muted text-[9px] text-fg-muted normal-case">
      ?
      <span className="pointer-events-none absolute top-full left-1/2 z-20 mt-1.5 w-64 -translate-x-1/2 bg-panel px-2.5 py-2 text-left font-sans text-[11.5px] font-normal normal-case tracking-normal text-panel-fg opacity-0 shadow-card transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
        Skill slots (QB/RB/WR/TE) score on real fantasy points. Trench and
        defensive slots (OL/DL/LB/CB/S/ST) score on Approximate Value
        instead — one scale that works across every position.
      </span>
    </span>
  );
}

/**
 * A drafted player's photo, chip-sized for a roster card. Falls back to
 * initials on a load failure or a missing headshot_url -- about 0.6% of the
 * pool has no portrait at all (see scripts/av_roster_pool/build_pool.py's own
 * coverage guard), and even a real URL can 404, so both cases render the same
 * way rather than a broken-image icon -- the same posture TeamLogo takes for
 * a missing franchise logo, minus the "just hide it" escape hatch: a jersey
 * number never had a bare-text fallback to fall back to, but a player's name
 * always does.
 */
function PlayerPortrait({ name, headshotUrl, className = "h-6 w-6" }: { name: string; headshotUrl?: string | null; className?: string }) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(headshotUrl) && !failed;
  return (
    <span aria-hidden="true" className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-panel-shade ${className}`}>
      {showImage ? (
        <img src={headshotUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        <span className="flex h-full w-full items-center justify-center bg-hidden font-slab text-[9px] text-panel"><span className="font-slab-optical-center">{initials(name)}</span></span>
      )}
    </span>
  );
}

function initials(name: string) {
  return (
    name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]?.toUpperCase()).join("") || "?"
  );
}

/**
 * RosterBoard's own seat avatar — a human player's profile photo, not a
 * drafted player's headshot (that's PlayerPortrait above). Same
 * onError-falls-back-to-initials posture, sized to match PlayerPortrait's
 * circular chips (see the comment at its call site).
 */
function RosterAvatar({ name, avatarUrl, mine }: { name: string; avatarUrl: string | null; mine: boolean }) {
  const [failed, setFailed] = useState(false);
  if (avatarUrl && !failed) {
    return <img src={avatarUrl} alt="" onError={() => setFailed(true)} className="h-7 w-7 shrink-0 rounded-full object-cover" />;
  }
  return (
    <span aria-hidden="true" className={`flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-full ${mine ? "ring-2 ring-hidden" : ""}`}>
      <GeneratedAvatar name={name} size={28} className="h-full w-full" />
    </span>
  );
}

function shuffle<T>(items: T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [copy[i], copy[j]] = [copy[j], copy[i]]; }
  return copy;
}

/**
 * "The turn" — what's publicly true right now, whether or not it's the
 * viewer's own action. A round's franchises are all dealt at once when the
 * round opens (see docs/games/sabotage_draft.md), so the reel isn't
 * revealing new information on every turn — it's re-announcing the turn
 * that's now current, the same instinct as a scoreboard calling out
 * possession rather than only silently changing a number.
 *
 * `revealed` comes from a single `useTurnReveal` call in the parent (shared
 * with the "Your move" column, so the two can't disagree about whether this
 * turn is still spinning) — see that hook's own doc comment for why the
 * reel's *correctness* never depends on whether the CSS animation below
 * actually plays. It only depends on `revealed`.
 *
 * Deliberately just the reel and its own headline -- the left column's other
 * job is TurnClock below, and a "This turn so far" guess/pass tracker and a
 * sabotage/respin hit flash used to live here too. Both are cut from this
 * screen for now (not redesigned elsewhere in this pass) so the column reads
 * as the two things that actually matter moment-to-moment: what's spinning,
 * and how long is left. A manual "Replay spin" button used to live here too
 * -- cut because it shared `revealed` with the "Your move" gating, so
 * replaying the animation also re-hid your own pick/guess form for 3s, a
 * side effect nobody wanted for a purely cosmetic replay.
 */
function TurnSpinner({ board, players, spins, revealed }: { board: Board; players: Player[]; spins: Spin[]; revealed: boolean }) {
  const activePlayer = players.find(p => p.user_id === board.active_user_id);
  const activeSpin = spins.find(s => s.round_number === board.current_round && s.user_id === board.active_user_id);
  const landedCode = activeSpin?.franchise_code ?? null;
  const landedName = activeSpin ? franchiseName(activeSpin.franchise_code) : null;

  // Pairs, not bare names, so every reel row -- decoy or real -- can carry
  // its own logo. Filtered by code rather than by display name: two
  // different franchise codes never collide on a name today, but identity is
  // the correct thing to compare regardless.
  const decoys = useMemo(
    () => shuffle(Object.entries(FRANCHISE_NAMES).filter(([code]) => code !== landedCode)).slice(0, 7),
    [landedCode],
  );
  const reelItems: [string, string][] = landedCode && landedName ? [...decoys, [landedCode, landedName]] : [];
  // Remounts (and so re-animates) the CSS reel on every new turn. This is
  // purely decorative timing -- it drives *when* the spin plays, never what
  // it ends up showing; see the `revealed` branch below.
  const reelKey = `${board.current_round}-${board.active_user_id}-${revealed}`;

  return (
    <Card edge={false} className="flex flex-col">
      <div className="relative mx-3 mt-3 h-24 overflow-hidden bg-panel-fg" aria-hidden="true">
        <span className="pointer-events-none absolute inset-x-0 top-0 z-10 h-4 bg-gradient-to-b from-panel-fg to-transparent" />
        <span className="pointer-events-none absolute inset-x-0 bottom-0 z-10 h-4 bg-gradient-to-t from-panel-fg to-transparent" />
        {!reelItems.length ? (
          <p className="flex h-24 items-center justify-center font-mono text-xs text-panel-muted uppercase">Waiting on the next spin…</p>
        ) : revealed ? (
          // The only place the real team is ever rendered idle -- not a side
          // effect of an animation having finished, so this is correct
          // whether or not motion played at all. Logo stacked above the name
          // and sized up so it reads as the headline element, the name a
          // caption underneath -- same idea as PastTurnCell/RosterBoard's
          // portrait-above-label pattern, applied here instead of the old
          // side-by-side row.
          <div className="flex h-24 flex-col items-center justify-center gap-1">
            <TeamLogo code={landedCode!} className="h-12 w-12" />
            <span className="font-slab text-lg tracking-[0.02em] text-panel uppercase">{landedName}</span>
          </div>
        ) : (
          <>
            {/* Motion-safe: the slot-machine scroll, timed to land on the
                real team exactly as useTurnReveal's delay elapses --
                animation-duration is set from TURN_REVEAL_MS inline so the
                two can't drift apart (see globals.css's .animate-reel-spin
                comment). Row height only needs to stay consistent across
                rows and match the container -- the keyframes translate by
                percentages of --reel-count, not a hardcoded pixel height. */}
            <SlotReel
              items={reelItems}
              durationMs={TURN_REVEAL_MS}
              reelKey={reelKey}
              viewportClassName="h-24"
              rowClassName="h-24 flex-col items-center justify-center gap-1 font-slab text-lg tracking-[0.02em] text-panel uppercase"
              itemKey={([code], index) => `${code}-${index}`}
              renderItem={([code, name]) => (
                <>
                  <TeamLogo code={code} className="h-12 w-12" />
                  {name}
                </>
              )}
            />
          </>
        )}
      </div>
      <div className="px-3 pt-3 pb-3">
        <p className="font-slab text-2xl leading-none uppercase">{activePlayer?.display_name ?? "…"} is picking</p>
        <p className="mt-1 font-mono text-[11px] tracking-[0.11em] text-panel-muted uppercase">
          {revealed && landedName ? `Spun the ${landedName}` : "Spinning…"} · choosing {board.slot === "X_FACTOR" ? "any offensive skill player" : `a ${board.slot.replace(/[0-9]/g, "")}`}
        </p>
      </div>
    </Card>
  );
}

/** Below this, the countdown reads in tenths (a shot clock's own
 *  convention) instead of jumping whole-second to whole-second. */
const TENTHS_THRESHOLD_MS = 5_000;

/**
 * The other half of the left column: how long is left on this turn, made as
 * prominent as the spinner above it rather than the single line of header
 * text it replaces. Shape and classes are a direct port of the auction's own
 * clock (AuctionMatch's BidBar, "Clock" section) -- label line, a big
 * countdown, a progress bar tied to the same TICK_MS the auction's animates
 * on, and the same "seconds <= 3 turns the whole card red" urgency rule,
 * reusing `hidden`/`hidden-text` (globals.css's "red means concealed" token,
 * repurposed the same way the auction's clock already repurposes it for
 * urgency). `label` is handed down rather than computed here so this stays a
 * dumb renderer that knows nothing about sabotage draft's own turn phases.
 *
 * The big number is font-mono (JetBrains Mono), not the app's usual
 * font-slab display face -- see layout.tsx's own comment that this face is
 * meant to carry "every stat line, budget, and clock" -- and, below
 * TENTHS_THRESHOLD_MS, reads in tenths the way a basketball shot clock
 * switches from whole seconds to "4.9, 4.8, ..." once time gets short.
 * Neither reading ever carries a unit suffix, on purpose: a bare `45` next
 * to a suffixed `4.9` would read as two different formats sharing one
 * number, not one countdown. `remainingMs` already ticks at TICK_MS
 * resolution (see useMatchClock's own doc comment), so this is a pure
 * formatting choice over data the hook already produces -- nothing here
 * asks it to poll any faster.
 */
function TurnClock({ label, remainingMs }: { label: string; remainingMs: number | null }) {
  const wholeSeconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);
  const fraction = remainingMs === null ? 0 : Math.min(1, remainingMs / (TURN_DURATION_MS - VISIBLE_SLACK_MS));
  const urgent = remainingMs !== null && remainingMs <= 3_000;
  const tone = urgent ? "border-hidden bg-hidden/10 text-hidden-text" : "border-line bg-surface-raised text-fg";
  const display =
    remainingMs === null
      ? "—"
      : remainingMs < TENTHS_THRESHOLD_MS
        ? (remainingMs / 1000).toFixed(1)
        : `${wholeSeconds}`;
  // The visible timer changes ten times a second (see globals.css's own note
  // on the auction's identical clock); the live region only speaks at these
  // three moments so it never narrates every intervening tick. Keyed off
  // wholeSeconds, not the tenths display -- a screen reader wants "3 seconds
  // left" once, not "3.2", "3.1", "3.0" in a row.
  const announcement = wholeSeconds !== null && [10, 5, 3].includes(wholeSeconds) ? `${wholeSeconds} seconds left` : "";

  return (
    <section aria-label="Clock" className={`rounded border p-3 transition-colors ${tone}`}>
      <p className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">{label || "Locked"}</p>
      <p className={`mt-1 font-mono text-5xl leading-none tabular-nums ${urgent ? "text-hidden-text" : ""}`} aria-hidden>
        {display}
      </p>
      <p aria-live="polite" className="sr-only">{announcement}</p>
      <div role="timer" aria-label={wholeSeconds === null ? "No timer" : `${wholeSeconds} seconds left`} className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-current/20">
        <div className="h-full bg-current" style={{ width: `${fraction * 100}%`, transition: `width ${TICK_MS}ms linear` }} />
      </div>
    </section>
  );
}

/**
 * The draft's memory. One cell per turn -- round x seated player, in the
 * same seat order the server deals turns in (active_seat resets to 0 at the
 * top of every round and increments by one per turn; see
 * supabase/migrations/20260826180000_0063_sabotage_draft_merged_turn.sql).
 *
 * Unlike the auction's LotStrip, there is no undealt cell here: every
 * franchise for every round is dealt up front and is public the whole game
 * (see docs/games/sabotage_draft.md), so even a turn nobody has reached yet
 * already has a real slot and franchise to show. What a cell withholds is
 * only ever the pick's own content -- identity and year -- exactly what
 * Table's concealed weave already withholds for the current round.
 */
function TurnStrip({ board, players, spins, picks, statuses, hits, viewerId }: { board: Board; players: Player[]; spins: Spin[]; picks: Pick[]; statuses: PickStatus[]; hits: Hit[]; viewerId: string }) {
  const seated = [...players].sort((a, b) => a.seat - b.seat);
  const activeIndex = seated.findIndex(p => p.user_id === board.active_user_id);
  const current = useRef<HTMLLIElement>(null);
  useEffect(() => { current.current?.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" }); }, [board.current_round, board.active_user_id]);

  return (
    <MatchStrip ariaLabel="Draft order">
      {Array.from({ length: board.round_count }, (_, i) => i + 1).flatMap(round => {
        const slot = slotForRound(round);
        return seated.map((player, seatIndex) => {
          const key = `${round}-${player.user_id}`;
          const spin = spins.find(s => s.round_number === round && s.user_id === player.user_id) ?? null;
          if (round === board.current_round && seatIndex === activeIndex) {
            return <CurrentTurnCell key={key} ref={current} round={round} slot={slot} player={player} spin={spin} />;
          }
          const past = round < board.current_round || (round === board.current_round && seatIndex < activeIndex);
          if (!past) return <FutureTurnCell key={key} round={round} slot={slot} player={player} spin={spin} />;
          const pick = picks.find(p => p.round_number === round && p.user_id === player.user_id) ?? null;
          const locked = statuses.some(s => s.round_number === round && s.user_id === player.user_id);
          const turnHits = hits.filter(h => h.round_number === round && h.target_user_id === player.user_id);
          return <PastTurnCell key={key} round={round} slot={slot} player={player} pick={pick} locked={locked} hits={turnHits} mine={player.user_id === viewerId} />;
        });
      })}
    </MatchStrip>
  );
}

function PastTurnCell({ round, slot, player, pick, locked, hits, mine }: { round: number; slot: string; player: Player; pick: Pick | null; locked: boolean; hits: Hit[]; mine: boolean }) {
  const respun = hits.some(h => h.kind === "respin");
  const sabotaged = hits.some(h => h.kind === "sabotage");
  const badge = respun && sabotaged ? "Respun · Sabotaged" : sabotaged ? "Sabotaged" : respun ? "Respun" : null;
  // `pick` is already scoped by RLS to exactly what this viewer may see —
  // their own pick any time, or anyone's once that pick's own round has
  // closed (see migration 0069's header) — so its presence alone is the
  // reveal signal. Once revealed, the cell's icon and name belong to the
  // drafted player, not the drafter; the drafter's own name moves up to the
  // label a round/slot pair used to occupy there, since that pairing is
  // already redundant with the cell's own position in the strip (the same
  // call RosterBoard already makes for its own round rows).
  return (
    <StripCell tone="settled" width={92} ariaLabel={`Round ${round}, ${player.display_name}, ${slot.replace("_", " ")}, ${pick ? `${pick.display_name} · ${pick.season}` : locked ? "Locked" : "not yet drafted"}${badge ? `, ${badge}` : ""}`}>
      <p className="truncate text-center font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted uppercase">{player.display_name}</p>
      <div className="relative w-fit mx-auto mb-1">
        {pick ? (
          <PlayerPortrait name={pick.display_name} headshotUrl={pick.headshot_url} className="mt-1 h-8 w-8" />
        ) : (
          <StripCellAvatar name={player.display_name} avatarUrl={player.avatar_url} mine={mine} />
        )}
        {badge ? <StripCellMediaBadge>{badge}</StripCellMediaBadge> : null}
      </div>
      <StripCellName center>{pick ? abbreviate(pick.display_name) : locked ? "Locked" : "—"}</StripCellName>
      {pick ? <StripCellCaption center>{pick.season}</StripCellCaption> : null}
    </StripCell>
  );
}

function CurrentTurnCell({ round, slot, player, spin, ref }: { round: number; slot: string; player: Player; spin: Spin | null; ref?: Ref<HTMLLIElement> }) {
  return (
    <StripCell tone="current" width={176} ref={ref}>
      <StripCellAvatar name={player.display_name} avatarUrl={player.avatar_url} big />
      <StripCellTextColumn>
        <StripCellTitle meta={`· ${slot.replace("_", " ")}`}>R{round}</StripCellTitle>
        <StripCellCaption>{player.display_name} on the clock</StripCellCaption>
        {spin ? <StripCellCaption icon={<TeamLogo code={spin.franchise_code} className="h-3 w-3" />}>{franchiseName(spin.franchise_code)}</StripCellCaption> : null}
      </StripCellTextColumn>
    </StripCell>
  );
}

function FutureTurnCell({ round, slot, player, spin }: { round: number; slot: string; player: Player; spin: Spin | null }) {
  return (
    <StripCell tone="upcoming" width={92} ariaLabel={`Round ${round}, ${player.display_name}, ${slot.replace("_", " ")}, not yet drafted`}>
      <p className="w-full truncate text-center font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted uppercase">R{round} · {slot.replace("_", " ")}</p>
      <StripCellAvatar name={player.display_name} avatarUrl={player.avatar_url} muted />
      <StripCellName center>{player.display_name}</StripCellName>
      {spin ? <StripCellCaption center icon={<TeamLogo code={spin.franchise_code} className="h-2.5 w-2.5" />}><span className="text-fg-muted/70">{franchiseName(spin.franchise_code)}</span></StripCellCaption> : null}
    </StripCell>
  );
}

/**
 * What the previous turn resolved to, standing in for "Spinning…" for as
 * long as the new turn's own reel is still spinning (see the effect that
 * builds `TurnResultData` in SabotageDraftMatch). `edge` reuses Card's own
 * "concealed from someone" rule: false for the viewer's own resolved turn --
 * nothing here is hidden from the one person reading it -- true for anyone
 * else's, where the identity behind `spin`/`slot` still is. `animate-sold-
 * headline` is the auction's own "Sold to" entrance, reused as-is for the
 * same "a result just landed" beat.
 */
function TurnResultCard({ result }: { result: TurnResultData }) {
  const { playerName, mine, pick, spin, slot, outcome, actorName } = result;
  const headline = outcome === "kept"
    ? mine ? "You kept the pick" : `${playerName} kept the pick`
    : outcome === "respun"
    ? `${actorName ?? "Someone"} forced a respin on ${mine ? "you" : playerName}`
    : `${actorName ?? "Someone"} sabotaged ${mine ? "you" : playerName}`;
  return (
    <Card className="animate-sold-headline" edge={!mine}>
      <div className="flex items-center gap-2.5 p-3">
        {mine && pick ? (
          <PlayerPortrait name={pick.display_name} headshotUrl={pick.headshot_url} className="h-10 w-10 shrink-0" />
        ) : spin ? (
          <TeamLogo code={spin.franchise_code} className="h-10 w-10 shrink-0" />
        ) : null}
        <div className="min-w-0">
          <p className="font-mono text-[10px] tracking-[0.14em] text-panel-muted uppercase">{headline}</p>
          <p className="truncate font-slab text-xl leading-none uppercase">
            {mine && pick ? `${pick.display_name} · ${pick.season}` : `${slot.replace("_", " ")}${spin ? ` · ${franchiseName(spin.franchise_code)}` : ""}`}
          </p>
        </div>
      </div>
    </Card>
  );
}

/**
 * "Everyone's teams" — every seated player's full 14-round roster, not just
 * the current round. A `<details>` per player, collapsed by default and
 * expanded on click, the same interaction the auction's own PlayerRail
 * already uses for its team panel; the viewer's own row is pinned first and
 * open by default, since it's the one row always worth checking.
 *
 * A pick's identity never reaches the wire for anyone but its owner (RLS on
 * sabotage_draft_picks is `user_id = auth.uid()` — see
 * supabase/migrations/20260822161000_0052_sabotage_draft_picks.sql), so
 * `picks` here is already scoped to the viewer's own rows; every other
 * seat's filled slot can only ever show what `statuses`/`spins`/`hits`
 * carry — a franchise and a hit badge, never a name.
 */
function RosterBoard({ board, players, spins, picks, statuses, hits, viewerId, justResolved }: { board: Board; players: Player[]; spins: Spin[]; picks: Pick[]; statuses: PickStatus[]; hits: Hit[]; viewerId: string; justResolved: TurnResultData | null }) {
  const seated = [...players].sort((a, b) => a.seat - b.seat);
  const seatIndexOf = new Map(seated.map((p, index) => [p.user_id, index]));
  const activeIndex = seatIndexOf.get(board.active_user_id) ?? -1;
  const ordered = [...players].sort((a, b) => (a.user_id === viewerId ? -1 : b.user_id === viewerId ? 1 : a.seat - b.seat));
  const rounds = Array.from({ length: board.round_count }, (_, i) => i + 1);

  return (
    <div className="sabotage-roster-board flex flex-col divide-y divide-line border border-line bg-surface-raised">
      {ordered.map(player => {
        const mine = player.user_id === viewerId;
        const active = player.user_id === board.active_user_id;
        const filledCount = statuses.filter(s => s.user_id === player.user_id).length;
        const hitCount = hits.filter(h => h.target_user_id === player.user_id).length;
        const seatIndex = seatIndexOf.get(player.user_id) ?? 0;
        const resolvedHere = justResolved?.userId === player.user_id ? justResolved : null;

        return (
          <details key={player.user_id} open={mine}>
            {/* A soft full-row wash rather than a thin edge accent -- the
                same "currently choosing" accent color already marks the
                active seat everywhere else (RosterBoard's own round rows,
                GuessForm), just applied to the whole row here so it reads at
                a glance without opening it. Plain hover:bg-panel/5 still
                applies on top for every other row; layering the two only
                deepens the tint further while active rather than fighting it.
                `resolvedHere` takes priority over `active` -- the two are
                mutually exclusive in practice anyway, since the turn that
                just resolved is never also the one currently on the clock --
                and flashes red for a hit or a neutral cream wash for a kept
                pick, reusing the auction's own `animate-sold-once` (a seat's
                roster row lighting up the instant a lot lands in it) for the
                same "something just landed here" beat. Applied at the
                summary level rather than inside the per-round row it
                actually happened on, because every row but the viewer's own
                starts collapsed (`open={mine}` below) -- a flash buried
                inside a closed <details> would go unseen for everyone but
                the player whose own turn it was. */}
            <summary className={`grid cursor-pointer grid-cols-[1.85rem_1fr_auto_1rem] items-center gap-2.5 px-3 py-2.5 hover:bg-panel/5 ${resolvedHere ? (resolvedHere.outcome === "kept" ? "bg-panel-fg/10 motion-safe:animate-sold-once" : "bg-hidden/15 motion-safe:animate-sold-once") : active ? "bg-hidden-ink/10" : ""}`}>
              {/* Rounded to match PlayerPortrait's own circular chips -- a
                  square initial avatar next to circular player portraits read
                  as two different avatar languages once portraits shipped. */}
              <RosterAvatar name={player.display_name} avatarUrl={player.avatar_url} mine={mine} />
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="flex items-center gap-1.5 font-slab text-base leading-none uppercase">
                  {mine ? "You" : player.display_name}
                  {mine ? <span className="font-mono text-[8px] tracking-[0.07em] text-hidden-text">YOU</span> : null}
                  {player.absent ? <span className="font-mono text-[8px] tracking-[0.07em] text-fg-muted">AWAY</span> : null}
                </span>
                <span className={`font-mono text-[9px] tracking-[0.07em] uppercase ${active ? "text-hidden-text" : "text-fg-muted"}`}>
                  {active ? "On the clock" : `${filledCount}/${board.round_count} filled`}
                </span>
              </span>
              {/* A pill rather than bare text once hits > 0 -- the same
                  reasoning as the round rows' bordered treatment: the shape
                  alone should say "something happened here" before anyone
                  reads the number. Zero stays plain text; there's nothing to
                  call out. */}
              {hitCount ? (
                <span className="whitespace-nowrap rounded-full bg-hidden/15 px-2 py-0.5 font-mono text-[9px] tracking-[0.06em] text-hidden-text uppercase">
                  {hitCount} hit{hitCount === 1 ? "" : "s"}
                </span>
              ) : (
                <span className="whitespace-nowrap font-mono text-[9px] tracking-[0.06em] text-fg-muted uppercase">No hits</span>
              )}
              <Chevron className="roster-chev h-4 w-4 shrink-0 text-fg-muted transition-transform" />
            </summary>
            <div className="px-2.5 pb-2.5">
              <div className="flex flex-col gap-1.5 bg-panel p-1.5 text-panel-fg">
                {rounds.map(round => {
                  const slot = slotForRound(round);
                  const filled = statuses.some(s => s.round_number === round && s.user_id === player.user_id);
                  const roundHits = hits.filter(h => h.round_number === round && h.target_user_id === player.user_id);
                  const respun = roundHits.some(h => h.kind === "respin");
                  const sabotaged = roundHits.some(h => h.kind === "sabotage");
                  const spin = spins.find(s => s.round_number === round && s.user_id === player.user_id);
                  const pick = picks.find(p => p.round_number === round && p.user_id === player.user_id);
                  const choosing = !filled && round === board.current_round && active;
                  const upNext = !filled && !choosing && round === board.current_round && seatIndex > activeIndex;
                  // Each round gets its own bordered slip rather than one flat
                  // divided list -- the border tone alone says what the row
                  // is without reading the text inside it: a revealed pick of
                  // your own stands out, a still-concealed one reads flat,
                  // and the seat currently on the clock gets the "choosing"
                  // accent this same accent color already carries elsewhere
                  // (GuessForm's exact-guess prompt, TurnPanel's flash).
                  const rowTone = filled && mine && pick
                    ? "border-hidden-text/40 bg-panel-fg/[0.05]"
                    : filled
                    ? "border-panel-fg/10 bg-panel-fg/[0.02]"
                    : choosing
                    ? "border-hidden-ink/50 bg-hidden-ink/10"
                    : "border-dashed border-panel-fg/10";
                  return (
                    <div key={round} className={`flex items-center justify-between gap-2 rounded border px-2.5 py-2 ${rowTone}`}>
                      {/* Round number dropped: slotForRound (see
                          lib/sabotage-draft/rounds.ts) is a fixed 1:1
                          round<->slot mapping, and these rows are already
                          rendered in round order, so "R{round}" was a third
                          label for information the slot and the row's own
                          position already carry. */}
                      <span className="shrink-0 font-mono text-[10px] tracking-[0.07em] text-panel-muted uppercase">{slot.replace("_", " ")}</span>
                      <span className="flex min-w-0 items-center gap-2 text-sm">
                        {/* `pick` is already scoped by RLS to exactly what this
                            viewer may see -- their own any time, or anyone's
                            once that seat's own turn has resolved (0073) --
                            so its presence alone is the reveal signal here,
                            the same call PastTurnCell already makes for the
                            turn strip above. `mine` no longer gates this: a
                            teammate's pick shows the instant RLS starts
                            returning the row, not only when it's your own. */}
                        {pick ? (
                          <span className="flex min-w-0 items-center gap-2">
                            <PlayerPortrait name={pick.display_name} headshotUrl={pick.headshot_url} className="h-6 w-6" />
                            <span className="truncate font-semibold">{pick.display_name} · {pick.season}</span>
                          </span>
                        ) : filled && mine ? (
                          <span className="truncate font-semibold">Locked</span>
                        ) : filled ? (
                          <Concealed label={`${player.display_name}'s concealed pick`} className="inline-flex shrink-0 items-center gap-1 px-1.5 py-0.5 font-mono text-[9px] tracking-[0.06em] uppercase">
                            {spin ? <TeamLogo code={spin.franchise_code} className="h-3 w-3" /> : null}
                            {spin ? franchiseName(spin.franchise_code) : "Locked"}
                          </Concealed>
                        ) : choosing ? (
                          <span className="font-mono text-[10px] tracking-[0.07em] text-hidden-ink uppercase">Choosing…</span>
                        ) : upNext ? (
                          <span className="font-mono text-[10px] text-panel-muted">— up next —</span>
                        ) : (
                          <span className="font-mono text-[10px] text-panel-muted">— not reached —</span>
                        )}
                        {respun ? <span className="shrink-0 bg-panel-shade px-1 py-0.5 font-mono text-[8px] tracking-[0.05em] text-panel-muted uppercase">Respun</span> : null}
                        {sabotaged ? <span className="shrink-0 bg-hidden px-1 py-0.5 font-mono text-[8px] tracking-[0.05em] text-panel uppercase">Sabotaged</span> : null}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </details>
        );
      })}
    </div>
  );
}

/** One player, grouped across every season they appear in this round's pool. */
type Tenured = { player_id: string; display_name: string; seasons: number[]; headshot_url: string | null };

function groupByPlayer(options: Option[]): Tenured[] {
  const map = new Map<string, Tenured>();
  for (const o of options) {
    const existing = map.get(o.player_id);
    // Every season's row for the same player carries the same portrait, but
    // a specific season a pool build had no fresher data for can still copy
    // a null headshot_url onto it -- keep the first real one any season
    // offers rather than letting a later null overwrite it.
    if (existing) existing.headshot_url ??= o.headshot_url;
    if (existing) existing.seasons.push(o.season);
    else map.set(o.player_id, { player_id: o.player_id, display_name: o.display_name, seasons: [o.season], headshot_url: o.headshot_url });
  }
  return [...map.values()].map(g => ({ ...g, seasons: [...g.seasons].sort((a, b) => b - a) }));
}

/** The row of season buttons a card or search result expands into. */
function SeasonChips({ seasons, pending, onChoose }: { seasons: number[]; pending: boolean; onChoose: (season: number) => void }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {seasons.map(season => (
        <button key={season} type="button" disabled={pending} onClick={() => onChoose(season)} className="cursor-pointer bg-panel px-2.5 py-1 font-mono text-xs text-panel-fg tabular-nums hover:bg-hidden-text hover:text-hidden-ink">{season}</button>
      ))}
    </div>
  );
}

/**
 * One of the three most-tenured cards. Collapsed, it's a portrait-forward
 * card a player recognizes at a glance. Tapping it (when a season still
 * needs picking) expands it into its own season chips, in place of a
 * separate "choose a year" screen. The caller always renders the expanded
 * card first, so it lands in the same top-left slot no matter which of the
 * three was tapped. Tapping the expanded card again collapses it back to a
 * plain choice, unpicking it.
 *
 * The outer `motion.div`'s `layout` prop is what makes all of that (the
 * reorder to the front, the resize into `col-span-3`, the other two cards
 * sliding to make room) read as one smooth move instead of a jump cut —
 * Motion diffs this element's box before/after each render and animates the
 * difference, with no per-property animation of our own to hand-tune.
 */
function TenuredCard({ rank, player, expanded, dimmed, pending, onSelect, onChooseSeason }: { rank: number; player: Tenured; expanded: boolean; dimmed: boolean; pending: boolean; onSelect: () => void; onChooseSeason: (season: number) => void }) {
  return (
    <motion.div layout transition={springSnappy} className={expanded ? "col-span-3" : undefined}>
      {expanded ? (
        <div className="flex flex-col gap-2 border border-hidden-text bg-surface-raised p-3">
          <button type="button" disabled={pending} onClick={onSelect} className="flex cursor-pointer items-center gap-2.5 text-left">
            <PlayerPortrait name={player.display_name} headshotUrl={player.headshot_url} className="h-10 w-10" />
            <span className="min-w-0 truncate font-slab text-lg leading-none uppercase text-fg">{player.display_name}</span>
          </button>
          <motion.div variants={dropdownUp} initial="initial" animate="animate">
            <SeasonChips seasons={player.seasons} pending={pending} onChoose={onChooseSeason} />
          </motion.div>
        </div>
      ) : (
        <button type="button" disabled={pending} onClick={onSelect} className={`flex w-full flex-col items-center gap-1.5 border border-line bg-surface-raised px-2 py-3 text-center hover:border-hidden-text ${dimmed ? "opacity-40" : ""}`}>
          <span className="relative">
            <PlayerPortrait name={player.display_name} headshotUrl={player.headshot_url} className="h-14 w-14" />
            <span aria-hidden="true" className="absolute -top-1 -left-1 flex h-4 w-4 items-center justify-center bg-panel font-mono text-[9px] text-panel-fg">{rank}</span>
          </span>
          <span className="flex min-w-0 flex-col items-center gap-0.5">
            <span className="w-full truncate font-slab text-sm leading-none uppercase text-fg">{player.display_name}</span>
            <span className="font-mono text-[9px] tracking-[0.06em] text-hidden-text">{player.seasons[player.seasons.length - 1]}–{player.seasons[0]}</span>
          </span>
        </button>
      )}
    </motion.div>
  );
}

/** One flat row the search dropdown can render — either a specific
 *  player+season (when the year is part of the decision) or a bare player
 *  (when it isn't), carrying the exact `Option` a click on it should submit. */
type SearchRow = { key: string; display_name: string; headshot_url: string | null; season: number | null; option: Option };

/**
 * A flat dropdown of every player this franchise/slot has ever fielded is a
 * wall for a team with decades of history at a slot. The three most tenured
 * players at the top are a one-tap shortcut for the read most people
 * actually have ("who played this position here the longest"); the search
 * dropdown underneath is the escape hatch for anyone else — every other
 * eligible player (and, when the year matters, every one of their seasons as
 * its own row), picked in one tap rather than a name-then-year expansion.
 *
 * `needsSeason` is false for a name-only guess, where the game itself never
 * checks the year — picking a player is the whole decision, so the dropdown
 * collapses to one row per player. It's true for a pick and for an exact
 * guess, where a specific season is part of what's being claimed, so each
 * season gets its own row. Choosing a top-3 card still expands in place into
 * that player's own seasons (see TenuredCard) — the dropdown's rows are
 * already specific enough to skip that second step.
 */
function PlayerPicker({ options, needsSeason, value, onChange, pending }: { options: Option[]; needsSeason: boolean; value: Option | null; onChange: (option: Option | null) => void; pending: boolean }) {
  const grouped = useMemo(() => groupByPlayer(options), [options]);
  const tenured = useMemo(() => [...grouped].sort((a, b) => b.seasons.length - a.seasons.length || b.seasons[0] - a.seasons[0]).slice(0, 3), [grouped]);
  const [query, setQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [expanded, setExpanded] = useState<Tenured | null>(null);
  // The dropdown is portaled to <body> (see below) so it isn't clipped by
  // whichever `Card` it's sitting inside — Card is `overflow-hidden` by
  // design (it clips the top edge strip to the card's rounded corners), and
  // this list needs to float above that, not be cropped by it. A portal
  // needs its own coordinates, since it's no longer a normal document-flow
  // child of the input it belongs to.
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [dropdownRect, setDropdownRect] = useState<{ top: number; left: number; width: number } | null>(null);
  const positionDropdown = useCallback(() => {
    const rect = searchInputRef.current?.getBoundingClientRect();
    if (rect) setDropdownRect({ top: rect.bottom, left: rect.left, width: rect.width });
  }, []);
  // Recomputed for as long as the dropdown is open, not just once on open —
  // a scroll or resize while it's up would otherwise leave it floating over
  // the wrong spot.
  useLayoutEffect(() => {
    if (!searchOpen) return;
    positionDropdown();
    window.addEventListener("resize", positionDropdown);
    window.addEventListener("scroll", positionDropdown, true);
    return () => { window.removeEventListener("resize", positionDropdown); window.removeEventListener("scroll", positionDropdown, true); };
  }, [searchOpen, positionDropdown]);
  // Rank badges track tenure, not screen position, so they're captured
  // before the expanded card gets pulled to the front of the row below.
  const rankByPlayer = useMemo(() => new Map(tenured.map((g, i) => [g.player_id, i + 1])), [tenured]);
  // "The rest" of the pool, not the top 3 — those already have their own
  // one-tap cards above, so repeating them here would just be a second way
  // to do the same thing.
  const searchRows: SearchRow[] = useMemo(() => {
    const rest = options.filter(o => !rankByPlayer.has(o.player_id));
    if (!needsSeason) {
      return groupByPlayer(rest)
        .sort((a, b) => a.display_name.localeCompare(b.display_name))
        .map(g => ({ key: g.player_id, display_name: g.display_name, headshot_url: g.headshot_url, season: null, option: { player_id: g.player_id, display_name: g.display_name, season: g.seasons[0], slot_category: rest.find(o => o.player_id === g.player_id)?.slot_category ?? "", headshot_url: g.headshot_url } }));
    }
    return [...rest]
      .sort((a, b) => a.display_name.localeCompare(b.display_name) || b.season - a.season)
      .map(o => ({ key: `${o.player_id}-${o.season}`, display_name: o.display_name, headshot_url: o.headshot_url, season: o.season, option: o }));
  }, [options, rankByPlayer, needsSeason]);
  const filteredRows = query.trim() ? searchRows.filter(r => r.display_name.toLowerCase().includes(query.trim().toLowerCase())) : searchRows;
  const orderedTenured = useMemo(() => {
    if (!expanded) return tenured;
    const match = tenured.find(g => g.player_id === expanded.player_id);
    return match ? [match, ...tenured.filter(g => g.player_id !== expanded.player_id)] : tenured;
  }, [tenured, expanded]);

  const choosePlayer = (g: Tenured) => {
    if (!needsSeason) { onChange({ player_id: g.player_id, display_name: g.display_name, season: g.seasons[0], slot_category: options.find(o => o.player_id === g.player_id)?.slot_category ?? "", headshot_url: g.headshot_url }); return; }
    setExpanded(current => (current?.player_id === g.player_id ? null : g));
  };
  const chooseSeason = (g: Tenured, season: number) => {
    onChange({ player_id: g.player_id, display_name: g.display_name, season, slot_category: options.find(o => o.player_id === g.player_id && o.season === season)?.slot_category ?? "", headshot_url: g.headshot_url });
    setExpanded(null);
  };

  if (value) {
    return (
      <div className="flex items-center justify-between gap-2 bg-surface-raised px-3 py-2.5 text-sm text-fg">
        <span className="flex min-w-0 items-center gap-2">
          <PlayerPortrait name={value.display_name} headshotUrl={value.headshot_url} className="h-7 w-7" />
          <span className="truncate"><span className="font-semibold">{value.display_name}</span> <span className="font-mono text-xs text-fg-muted">· {value.season}</span></span>
        </span>
        <button type="button" disabled={pending} onClick={() => { onChange(null); setExpanded(null); }} className="cursor-pointer shrink-0 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase underline underline-offset-2">Change</button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {tenured.length ? (
        <div className="grid grid-cols-3 gap-1.5">
          {orderedTenured.map(g => (
            <TenuredCard
              key={g.player_id}
              rank={rankByPlayer.get(g.player_id)!}
              player={g}
              expanded={expanded?.player_id === g.player_id}
              dimmed={expanded !== null && expanded.player_id !== g.player_id}
              pending={pending}
              onSelect={() => choosePlayer(g)}
              onChooseSeason={season => chooseSeason(g, season)}
            />
          ))}
        </div>
      ) : null}
      {/* `onBlur`'s `relatedTarget` check is what closes the dropdown on an
          outside click, while a row's own `onMouseDown` preventDefault below
          keeps a tap on a row from blurring the input before its `onClick`
          fires — the list is portaled out of this div (see dropdownRect's
          own comment), so that check only has the input itself to compare
          against, but that's already enough since preventDefault stops focus
          from ever leaving the input on a row tap. */}
      <div onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setSearchOpen(false); }}>
        <div className="relative">
          <input
            ref={searchInputRef}
            type="text"
            aria-label="Search a player"
            placeholder="Search a name…"
            value={query}
            onFocus={() => setSearchOpen(true)}
            onChange={e => { setQuery(e.target.value); setSearchOpen(true); }}
            className="w-full bg-surface-raised px-3 py-2 pr-8 text-sm text-fg placeholder:text-fg-muted"
          />
          {/* Same rotate-on-open chevron as RosterBoard's own disclosure
              triangle (see globals.css's .roster-chev) — the one existing
              "this expands" affordance in this app, reused here so a search
              field that's secretly a dropdown reads as one at a glance. */}
          <Chevron className={`pointer-events-none absolute top-1/2 right-3 h-4 w-4 -translate-y-1/2 text-fg-muted transition-transform ${searchOpen ? "-rotate-90" : "rotate-90"}`} />
        </div>
        {searchOpen && dropdownRect
          ? createPortal(
              <ul
                style={{ position: "fixed", top: dropdownRect.top, left: dropdownRect.left, width: dropdownRect.width }}
                className="z-50 mt-1 max-h-56 overflow-y-auto border border-line bg-surface-raised shadow-card"
              >
                {filteredRows.length ? filteredRows.map(row => (
                  <li key={row.key}>
                    <button
                      type="button"
                      disabled={pending}
                      onMouseDown={e => e.preventDefault()}
                      onClick={() => { onChange(row.option); setQuery(""); setSearchOpen(false); }}
                      className="flex w-full cursor-pointer items-center justify-between gap-2 px-3 py-1.5 text-left text-sm text-fg hover:bg-white/5"
                    >
                      <span className="flex min-w-0 items-center gap-2">
                        <PlayerPortrait name={row.display_name} headshotUrl={row.headshot_url} className="h-6 w-6" />
                        <span className="truncate">{row.display_name}</span>
                      </span>
                      {row.season !== null ? <span className="shrink-0 font-mono text-[10px] text-fg-muted tabular-nums">{row.season}</span> : null}
                    </button>
                  </li>
                )) : (
                  <li className="px-3 py-2 font-mono text-xs text-fg-muted uppercase">No matches</li>
                )}
              </ul>,
              document.body,
            )
          : null}
      </div>
    </div>
  );
}

function PickForm({ options, mine, pending, onSubmit }: { options: Option[]; mine?: Pick; pending: boolean; onSubmit: (o: Option) => void }) {
  const [option, setOption] = useState<Option | null>(null);
  if (mine) return (
    <Card>
      <div className="flex items-center gap-2.5 px-3 pt-3">
        <PlayerPortrait name={mine.display_name} headshotUrl={mine.headshot_url} className="h-9 w-9" />
        <div className="min-w-0">
          <p className="font-slab text-2xl leading-none uppercase">Your pick is locked</p>
          <p className="mt-1 truncate font-mono text-[11px] tracking-[0.11em] text-panel-muted uppercase">{mine.display_name} · {mine.season} · waiting on the rest of the table</p>
        </div>
      </div>
      <div className="pb-3" />
    </Card>
  );
  return (
    <Card>
      <CardTitle>Make your hidden pick</CardTitle>
      <div className="flex flex-col gap-3 p-3 pt-0">
        <PlayerPicker options={options} needsSeason value={option} onChange={setOption} pending={pending} />
        <Button disabled={!option || pending} onClick={() => option && onSubmit(option)}>Lock in pick</Button>
      </div>
    </Card>
  );
}
// The guess window is aimed at whoever currently holds the turn, not a
// choice the guesser makes — so there is no target selector here, only the
// active drafter's own eligible pool, reloaded whenever the turn changes.
// Guessing and passing are the same one action a seat gets per turn: once
// either is spent, both controls disappear in favor of a locked-in state.
function GuessForm({ targetName, status, pending, loadOptions, onSubmit, onPass }: { targetName: string; status: "open" | "guessed" | "passed"; pending: boolean; loadOptions: () => Promise<Option[]>; onSubmit: (choice: Option, exact: boolean, replacement?: Option) => void; onPass: () => void }) {
  const [options, setOptions] = useState<Option[]>([]);
  // Which of the two guess types this turn spends (see docs/games/
  // sabotage_draft.md's "Two guesses, two different weapons"): a name-only
  // guess is cheap, uncontrolled chaos -- right, and the same player is
  // respun to a random *different year*, no choice for anyone, and no
  // erasing who they picked. Naming the exact year is the harder guess, and
  // pays off with a deliberate, aimed replacement the guesser chooses
  // themselves. That's not an optional extra step tacked onto one guess,
  // it's a choice between two different actions with very different stakes
  // -- so it's asked up front, as its own screen, not folded into a
  // checkbox sitting next to the picker.
  const [mode, setMode] = useState<"name" | "exact" | null>(null);
  const [guess, setGuess] = useState<Option | null>(null);
  const [replacement, setReplacement] = useState<Option | null>(null);
  useEffect(() => { let cancelled = false; void loadOptions().then(o => { if (!cancelled) setOptions(o); }); return () => { cancelled = true; }; }, [loadOptions]);
  if (status !== "open") return <Card><CardTitle>{status === "passed" ? "You passed on this turn" : "Guess spent on this turn"}</CardTitle><CardMeta>Waiting on the rest of the table</CardMeta></Card>;
  const chooseMode = (m: "name" | "exact" | null) => { setMode(m); setGuess(null); setReplacement(null); };
  // A guess changed after the fact restarts the replacement step -- it was
  // an answer to a question that's now being redone.
  const chooseGuess = (choice: Option | null) => { setGuess(choice); setReplacement(null); };

  // Mode isn't chosen yet: the only thing on screen is the choice itself,
  // spelled out as two labeled options rather than a checkbox plus caption,
  // so the stakes it sets are legible before anyone commits to it.
  if (!mode) return (
    <Card>
      <CardTitle>Sabotage {targetName}&apos;s pick</CardTitle>
      <div className="flex flex-col gap-2 p-3 pt-0">
        <button type="button" disabled={pending} onClick={() => chooseMode("name")} className="flex w-full flex-col items-start gap-0.5 border border-line bg-surface-raised px-3 py-2.5 text-left hover:border-hidden-text">
          <span className="text-sm font-semibold text-fg">Guess the player</span>
          <span className="font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">Right? Same player, a random different year — you don&apos;t choose it</span>
        </button>
        <button type="button" disabled={pending} onClick={() => chooseMode("exact")} className="flex w-full flex-col items-start gap-0.5 border border-line bg-surface-raised px-3 py-2.5 text-left hover:border-hidden-text">
          <span className="text-sm font-semibold text-fg">Guess the player and year</span>
          <span className="font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">Right? You choose exactly what replaces it</span>
        </button>
        <Button variant="ghost" className="!bg-surface-raised" disabled={pending} onClick={onPass}>Pass</Button>
      </div>
    </Card>
  );

  // Mode is chosen: from here the guess step is one PlayerPicker and one
  // button, the same shape as PickForm's "Make your hidden pick" -- exact
  // mode just has a second one of those (the replacement) queued up behind
  // it, in place of a free choice at the top. See PlayerPicker's own
  // collapsed-value row for the "Change" pattern reused below.
  const exact = mode === "exact";
  const showReplacementStep = exact && guess;
  return (
    <Card>
      <CardTitle>Sabotage {targetName}&apos;s pick</CardTitle>
      <div className="flex flex-col gap-3 p-3 pt-0">
        <div className="flex items-center justify-between gap-2 bg-surface-raised px-3 py-2 text-sm text-fg">
          <span>{exact ? "Guessing the player and year" : "Guessing the player"}</span>
          <button type="button" disabled={pending} onClick={() => chooseMode(null)} className="cursor-pointer shrink-0 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase underline underline-offset-2">Change</button>
        </div>
        <div className="flex flex-col gap-1.5">
          {exact ? <p className="font-mono text-[10px] tracking-[0.08em] text-panel-muted uppercase">Step 1 of 2 — guess the player</p> : null}
          <PlayerPicker options={options} needsSeason={exact} value={guess} onChange={chooseGuess} pending={pending} />
        </div>
        {showReplacementStep ? (
          <div className="flex flex-col gap-1.5">
            <p className="font-mono text-[10px] tracking-[0.08em] text-panel-muted uppercase">Step 2 of 2 — choose their replacement</p>
            <PlayerPicker options={options} needsSeason value={replacement} onChange={setReplacement} pending={pending} />
          </div>
        ) : null}
        <div className="flex gap-2">
          <Button className="flex-1" disabled={!guess || (exact && !replacement) || pending} onClick={() => guess && onSubmit(guess, exact, replacement ?? undefined)}>Lock in guess</Button>
          <Button variant="ghost" fullWidth={false} className="!bg-surface-raised" disabled={pending} onClick={onPass}>Pass</Button>
        </div>
      </div>
    </Card>
  );
}
export function xFactorReplacementSlots(pick: Pick | undefined, options: Option[]): string[] {
  const category = pick && options.find(option => option.player_id === pick.player_id && option.season === pick.season)?.slot_category;
  if (category === "QB" || category === "TE") return [category];
  if (category === "RB") return ["RB1", "RB2"];
  if (category === "WR") return ["WR1", "WR2", "WR3"];
  return [];
}

function Decision({ mine, pending, replacementSlots, onSubmit }: { mine?: Decision; pending: boolean; replacementSlots: string[]; onSubmit: (slot: string | null) => void }) { if (mine) return <Card><CardTitle>X-Factor decision locked</CardTitle><CardMeta>{mine.replace_slot ? `Replaces ${mine.replace_slot}` : "Discarded"}</CardMeta></Card>; return <Card><CardTitle>Assign or discard your X-Factor</CardTitle><div className="grid grid-cols-2 gap-2 p-3 pt-0">{replacementSlots.map(slot => <Button key={slot} variant="ink" disabled={pending} onClick={() => onSubmit(slot)}>Replace {slot}</Button>)}<Button className="col-span-2" disabled={pending} onClick={() => onSubmit(null)}>Discard X-Factor</Button></div></Card>; }
/**
 * The season's ending: seventeen simulated games boiled down to a record and
 * a letter grade per table, ranked and shown the same way every other
 * game's own final screen now does (components/game-runtime/FinalStandings)
 * — rank, avatar, name, record, and (unique to this game) a roster that
 * expands into the thirteen skill-slot picks and any accepted X-Factor
 * swap behind that grade, each with its own photo and its own
 * position-relative grade pulled from `pickAvs` (0074). Nobody at the
 * table knows what "93 AV" means; everybody knows what a B+ means — see
 * lib/sabotage-draft/grades.ts for where both scales actually come from.
 *
 * `standings.tiebreak_rank` is only ever unique *within* a shared win count
 * — 0056's own tiebreak bracket resolves ties inside a wins group, not
 * across the whole table — so the row actually shown here is 1-based array
 * position after the same (wins desc, tiebreak_rank asc) sort the old
 * screen used, not that raw column. Wins differ across every group and
 * tiebreak_rank fully resolves ties within one, so that sort is already a
 * total order: no two players ever land on the same position, and there is
 * always exactly one winner.
 */
function Final({ matchId, roomCode, isHost, viewerId, standings, players, tiebreaks, picks, decisions, pickAvs }: { matchId: string; roomCode: string | null; isHost: boolean; viewerId: string; standings: Standing[]; players: Player[]; tiebreaks: Tiebreak[]; picks: Pick[]; decisions: Decision[]; pickAvs: PickAv[] }) {
  const name = (id: string) => players.find(p => p.user_id === id)?.display_name ?? "Unknown";
  const avatarOf = (id: string) => players.find(p => p.user_id === id)?.avatar_url ?? null;
  const ranked = [...standings].sort((a, b) => b.wins - a.wins || a.tiebreak_rank - b.tiebreak_rank);
  const headline = ranked.length ? `${name(ranked[0].user_id)} wins` : "Season over";

  const rows: FinalStandingsRow[] = ranked.map((s, index) => ({
    userId: s.user_id,
    rank: index + 1,
    name: name(s.user_id),
    avatarUrl: avatarOf(s.user_id),
    isViewer: s.user_id === viewerId,
    statLine: `${s.wins}-${s.losses}`,
    endMetric: (
      <span className="flex min-w-[4.75rem] flex-col items-end gap-2">
        <span className="font-mono text-[8px] leading-none tracking-[0.12em] text-panel-muted uppercase">Draft grade</span>
        <GradeBadge grade={gradeForTeam(s.roster_strength)} emphasis="standings" />
      </span>
    ),
    roster: <SabotageRosterFinal userId={s.user_id} picks={picks} decisions={decisions} pickAvs={pickAvs} />,
  }));

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 px-4 py-8">
      <FinalStandings headline={headline} rows={rows} />
      {tiebreaks.length ? <TiebreakBracket tiebreaks={tiebreaks} players={players} viewerId={viewerId} /> : null}
      {roomCode ? <PostGameNavigation matchId={matchId} roomCode={roomCode} /> : null}
      {roomCode ? <PostGameControls matchId={matchId} roomCode={roomCode} isHost={isHost} /> : null}
    </main>
  );
}

/**
 * A saved tiebreak is a sequence of actual one-game matchups, not just an
 * explanation for the final order. Keep each tied record in its own board:
 * separate record groups never meet, while the columns preserve the rounds
 * inside one group's single-elimination run.
 */
function TiebreakBracket({ tiebreaks, players, viewerId }: { tiebreaks: Tiebreak[]; players: Player[]; viewerId: string }) {
  const brackets = new Map<number, Tiebreak[]>();
  for (const game of tiebreaks) brackets.set(game.record_wins, [...(brackets.get(game.record_wins) ?? []), game]);
  const player = (id: string) => players.find(p => p.user_id === id);

  return (
    <Card>
      <CardTitle>Tiebreak bracket</CardTitle>
      <div className="flex flex-col gap-5 p-3 pt-2">
        {[...brackets.entries()].sort(([a], [b]) => b - a).map(([wins, games]) => {
          const rounds = new Map<number, Tiebreak[]>();
          for (const game of games) rounds.set(game.bracket_round, [...(rounds.get(game.bracket_round) ?? []), game]);
          const orderedRounds = [...rounds.entries()].sort(([a], [b]) => a - b);
          const record = `${wins}-${17 - wins}`;

          return (
            <section key={wins} aria-labelledby={`tiebreak-${wins}`}>
              <header className="mb-2 flex items-baseline justify-between border-b border-panel-shade pb-2">
                <h3 id={`tiebreak-${wins}`} className="font-slab text-xl leading-none uppercase">{record} tiebreak</h3>
                <span className="font-mono text-[9px] tracking-[0.13em] text-panel-muted uppercase">One-game playoff</span>
              </header>
              <motion.div variants={tiebreakBoardReveal} initial="initial" animate="animate" className="overflow-x-auto pb-1">
                <div className="flex min-w-max gap-5 rounded-sm bg-surface p-3 shadow-well">
                  {orderedRounds.map(([round, roundGames], roundIndex) => (
                    <motion.div key={round} variants={tiebreakRoundReveal(roundIndex)} initial="initial" animate="animate" className="flex w-48 flex-col gap-2">
                      <p className="font-mono text-[9px] tracking-[0.13em] text-fg-muted uppercase">
                        {orderedRounds.length === 1 ? "Final" : roundIndex === orderedRounds.length - 1 ? "Final" : `Round ${round}`}
                      </p>
                      <div className={`flex min-h-24 flex-1 flex-col gap-3 ${roundIndex === 0 ? "justify-start" : "justify-around"}`}>
                        {roundGames.sort((a, b) => a.game_number - b.game_number).map((game, gameIndex) => (
                          <BracketMatch
                            key={`${game.bracket_round}-${game.game_number}`}
                            game={game}
                            playerA={player(game.player_a)}
                            playerB={game.player_b ? player(game.player_b) : undefined}
                            viewerId={viewerId}
                            reveal={tiebreakMatchReveal(roundIndex, gameIndex)}
                            revealDelay={1.22 + roundIndex * 0.32 + gameIndex * 0.1}
                          />
                        ))}
                      </div>
                    </motion.div>
                  ))}
                </div>
              </motion.div>
            </section>
          );
        })}
      </div>
    </Card>
  );
}

function BracketMatch({ game, playerA, playerB, viewerId, reveal, revealDelay }: { game: Tiebreak; playerA?: Player; playerB?: Player; viewerId: string; reveal: ReturnType<typeof tiebreakMatchReveal>; revealDelay: number }) {
  const wonA = game.winner_user_id === game.player_a;
  const playerName = (player: Player | undefined) => player?.display_name ?? "Unknown";

  if (!game.player_b) {
    return (
      <motion.article variants={reveal} initial="initial" animate="animate" className="border border-line bg-surface-raised px-2.5 py-2">
        <div className="flex items-center gap-2 text-sm text-fg">
          <RosterAvatar name={playerName(playerA)} avatarUrl={playerA?.avatar_url ?? null} mine={playerA?.user_id === viewerId} />
          <span className="min-w-0 flex-1 truncate font-slab text-base uppercase">{playerName(playerA)}</span>
          <span className="font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">Bye</span>
        </div>
        <p className="mt-1 pl-9 font-mono text-[9px] tracking-[0.08em] text-fg-muted uppercase">Advances</p>
      </motion.article>
    );
  }

  return (
    <motion.article variants={reveal} initial="initial" animate="animate" className="border border-line bg-surface-raised">
      <BracketCompetitor player={playerA} score={game.player_a_score} winner={wonA} viewerId={viewerId} revealDelay={revealDelay} />
      <BracketCompetitor player={playerB} score={game.player_b_score} winner={!wonA} viewerId={viewerId} revealDelay={revealDelay} />
    </motion.article>
  );
}

function BracketCompetitor({ player, score, winner, viewerId, revealDelay }: { player?: Player; score: number | null; winner: boolean; viewerId: string; revealDelay: number }) {
  const name = player?.display_name ?? "Unknown";
  return (
    <motion.div
      initial={{ opacity: 0, x: winner ? -6 : 4 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.22, ease: [0.16, 1, 0.3, 1], delay: revealDelay + (winner ? 0.1 : 0) }}
      className={`flex items-center gap-2 px-2 py-1.5 ${winner ? "bg-panel text-panel-fg" : "text-fg-muted"}`}
    >
      <RosterAvatar name={name} avatarUrl={player?.avatar_url ?? null} mine={player?.user_id === viewerId} />
      <span className={`min-w-0 flex-1 truncate font-slab text-base leading-none uppercase ${winner ? "text-panel-fg" : "text-fg"}`}>{name}</span>
      <motion.span
        initial={{ opacity: 0, y: -5, scale: 0.75 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.2, ease: [0.16, 1, 0.3, 1], delay: revealDelay + (winner ? 0.2 : 0.08) }}
        className={`font-mono text-sm font-bold tabular-nums ${winner ? "text-grade-elite" : "text-fg-muted"}`}
      >
        {score ?? "—"}
      </motion.span>
    </motion.div>
  );
}

/**
 * One table's final roster: all thirteen picks in round order — the seven
 * offensive skill slots and the six defense/OL/ST slots ROUND_SLOTS deals
 * right after them, not just the first seven — plus, when accepted, the
 * X-Factor swap replacing whichever (offense-only, per 0055's own check)
 * slot it targeted, shown as a strikeout of the discarded card's name
 * rather than just disappearing it. Each player gets their own photo
 * (PlayerPortrait, same component the live turn strip and roster board
 * already use) and their own position-relative letter grade — see
 * lib/sabotage-draft/grades.ts — built from `pickAvs`, keyed by (round,
 * user). See 0074's own visibility note for why that lookup can come back
 * empty for a pick nobody besides its owner has actually seen yet (a
 * still-live table reaching this screen mid-round would be the only way,
 * and even then a viewer's own picks always resolve).
 */
function SabotageRosterFinal({ userId, picks, decisions, pickAvs }: { userId: string; picks: Pick[]; decisions: Decision[]; pickAvs: PickAv[] }) {
  const avFor = (round: number) => pickAvs.find(a => a.round_number === round && a.user_id === userId)?.av ?? null;
  const decision = decisions.find(d => d.user_id === userId);
  const xFactorPick = decision?.replace_slot ? (picks.find(p => p.round_number === X_FACTOR_ROUND && p.user_id === userId) ?? null) : null;
  const xFactorAv = xFactorPick ? avFor(X_FACTOR_ROUND) : null;

  return (
    <dl className="flex flex-col gap-2">
      {ROUND_SLOTS.map((slot, i) => {
        const round = i + 1;
        const pick = picks.find(p => p.round_number === round && p.user_id === userId);
        const replaced = decision?.replace_slot === slot;
        const shown = replaced && xFactorPick ? xFactorPick : pick;
        const av = replaced && xFactorPick ? xFactorAv : avFor(round);
        return (
          <div key={slot} className="flex items-center gap-2.5">
            <dt className="w-9 shrink-0 font-mono text-[10px] tracking-[0.05em] text-panel-muted uppercase">{slot.replace("_", " ")}</dt>
            <PlayerPortrait name={shown?.display_name ?? "?"} headshotUrl={shown?.headshot_url} className="h-7 w-7" />
            <dd className="min-w-0 flex-1 truncate text-[11px] text-panel-fg normal-case">
              {shown ? (
                <>
                  {shown.display_name} · {shown.season}
                  {replaced && pick ? <s className="ml-1.5 text-[10px] text-panel-muted/70">{pick.display_name}</s> : null}
                </>
              ) : (
                <span className="text-panel-muted">—</span>
              )}
            </dd>
            <GradeBadge grade={shown && av !== null ? gradeForPick(slot, av) : null} />
          </div>
        );
      })}
    </dl>
  );
}

/**
 * A compact, editorial scoremark rather than a generic pill. Grades are
 * intentionally color-coded without using the app's concealed red: red is
 * reserved for information one player knows and another does not, while a
 * poor grade is fully public feedback. `null` (no AV to grade yet, or
 * nothing drafted into this slot) stays deliberately quiet.
 */
function GradeBadge({ grade, emphasis = "roster" }: { grade: string | null; emphasis?: "roster" | "standings" }) {
  const tone = grade ? grade.startsWith("A") ? "elite" : grade.startsWith("B") ? "strong" : grade.startsWith("C") ? "even" : "rough" : "pending";

  return (
    <span
      aria-label={grade ? `Grade ${grade}` : "No grade yet"}
      className={`grade-scoremark grade-scoremark--${tone} grade-scoremark--${emphasis}`}
    >
      {grade ?? "—"}
    </span>
  );
}
