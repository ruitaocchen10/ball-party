"use client";
/* eslint-disable @typescript-eslint/no-explicit-any -- Supabase types are regenerated after this migration lands. */

import { AnimatePresence, motion } from "motion/react";
import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type Ref } from "react";

import { PauseBanner } from "@/components/game-runtime/PauseBanner";
import { PauseButton } from "@/components/game-runtime/PauseButton";
import { AnimatedMessage } from "@/components/motion/AnimatedMessage";
import { Button } from "@/components/ui/Button";
import { Card, CardMeta, CardTitle } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import { HEARTBEAT_MS, VISIBLE_SLACK_MS, useMatchClock } from "@/lib/game-runtime/useMatchClock";
import { staggerRow } from "@/lib/motion";
import { FRANCHISE_NAMES, franchiseName } from "@/lib/sabotage-draft/franchises";
import { slotForRound } from "@/lib/sabotage-draft/rounds";
import { createClient, createRealtimeClient } from "@/lib/supabase/client";

// One shared clock per turn (see docs/games/sabotage_draft.md): the active
// seat may lock a pick any time within turn_deadline, and every other seat
// may lock in one guess or one pass any time within that same window,
// including before the pick exists. A guess's `result` is therefore nullable
// — pending until the whole turn's action set is complete — and there is no
// longer a separate pick/guess phase to key UI off of, only "is the turn
// open" and "have I already acted."
type Board = { match_id: string; round_count: number; current_round: number; slot: string; turn_deadline: string | null; server_now: string; x_factor_open: boolean; active_user_id: string };
type Player = { match_id: string; user_id: string; seat: number; absent: boolean; display_name: string };
type Spin = { match_id: string; round_number: number; user_id: string; franchise_code: string };
type Pick = { match_id: string; round_number: number; user_id: string; player_id: string; display_name: string; season: number; by_timeout: boolean };
type PickStatus = { match_id: string; round_number: number; user_id: string };
type Hit = { match_id: string; round_number: number; target_user_id: string; kind: "respin" | "sabotage" };
type Guess = { match_id: string; round_number: number; user_id: string; target_user_id: string; result: "miss" | "respun" | "sabotaged" | null };
type Pass = { match_id: string; round_number: number; target_user_id: string; user_id: string };
type Option = { player_id: string; display_name: string; season: number; slot_category: string };
type Decision = { match_id: string; user_id: string; replace_slot: string | null };
type Standing = { user_id: string; roster_strength: number; wins: number; losses: number; tiebreak_rank: number };
type Tiebreak = { record_wins: number; bracket_round: number; game_number: number; player_a: string; player_b: string | null; winner_user_id: string };

const MESSAGE: Record<string, string> = { already_picked: "Your pick is already locked.", already_acted: "You have already guessed or passed on this turn.", turn_closed: "This turn has closed.", invalid_pick: "Choose a player from this round's pool.", invalid_guess: "Choose a player from this round's pool.", match_not_playing: "This match isn't accepting moves right now.", not_your_turn: "It isn't your turn right now." };
const skillSlots = ["QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE"];

export function SabotageDraftMatch({ matchId, viewerId, isHost = false, paused = false, initial }: { matchId: string; viewerId: string; isHost?: boolean; paused?: boolean; initial: { board: Board; players: Player[]; spins: Spin[]; picks: Pick[]; statuses: PickStatus[]; hits: Hit[]; guesses: Guess[]; passes: Pass[]; decisions: Decision[]; standings: Standing[]; tiebreaks: Tiebreak[] } }) {
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);
  const [board, setBoard] = useState(initial.board); const [players, setPlayers] = useState(initial.players); const [spins, setSpins] = useState(initial.spins);
  const [picks, setPicks] = useState(initial.picks); const [statuses, setStatuses] = useState(initial.statuses);
  const [hits, setHits] = useState(initial.hits); const [guesses, setGuesses] = useState(initial.guesses); const [passes, setPasses] = useState(initial.passes);
  const [decisions, setDecisions] = useState(initial.decisions); const [standings, setStandings] = useState(initial.standings); const [tiebreaks, setTiebreaks] = useState(initial.tiebreaks);
  const [options, setOptions] = useState<Option[]>([]); const [error, setError] = useState<string | null>(null); const [pending, setPending] = useState(false);
  const [isPaused, setIsPaused] = useState(paused);
  const stateFrom = (row: Partial<Board>) => row.server_now && row.current_round && row.slot ? setBoard(previous => ({ ...previous, ...row } as Board)) : undefined;
  const refetch = useCallback(async () => {
    const s: any = getClient(); const [state, ps, spinResult, picksResult, statusResult, hitResult, guessResult, passResult, decisionResult, standingResult, tieResult] = await Promise.all([
      s.schema("sabotage_draft" as never).rpc("state" as never, { p_match_id: matchId } as never), s.from("sabotage_draft_players").select("*, profiles(display_name)").eq("match_id", matchId).order("seat"), s.from("sabotage_draft_round_spins").select("*").eq("match_id", matchId), s.from("sabotage_draft_picks").select("*").eq("match_id", matchId), s.from("sabotage_draft_pick_statuses").select("*").eq("match_id", matchId), s.from("sabotage_draft_pick_hits").select("*").eq("match_id", matchId), s.from("sabotage_draft_guesses").select("*").eq("match_id", matchId), s.from("sabotage_draft_passes").select("*").eq("match_id", matchId), s.from("sabotage_draft_x_factor_decisions").select("*").eq("match_id", matchId), s.from("sabotage_draft_standings").select("*").eq("match_id", matchId), s.from("sabotage_draft_tiebreak_games").select("*").eq("match_id", matchId),
    ]);
    if (state.data) stateFrom(state.data as Board); if (ps.data) setPlayers(ps.data.map(({ profiles, ...p }: any) => ({ ...p, display_name: profiles?.display_name ?? "Unknown player" })));
    if (spinResult.data) setSpins(spinResult.data as Spin[]);
    if (picksResult.data) setPicks(picksResult.data as Pick[]); if (statusResult.data) setStatuses(statusResult.data as PickStatus[]); if (hitResult.data) setHits(hitResult.data as Hit[]); if (guessResult.data) setGuesses(guessResult.data as Guess[]); if (passResult.data) setPasses(passResult.data as Pass[]); if (decisionResult.data) setDecisions(decisionResult.data as Decision[]); if (standingResult.data) setStandings(standingResult.data as Standing[]); if (tieResult.data) setTiebreaks(tieResult.data as Tiebreak[]);
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
  const call = async (name: string, args: Record<string, unknown>) => { setPending(true); setError(null); const { error: rpcError } = await (getClient().schema("sabotage_draft" as never).rpc(name as never, args as never) as any); setPending(false); if (rpcError) setError(MESSAGE[rpcError.message] ?? rpcError.message); else await refetch(); };
  const myPick = picks.find(p => p.round_number === board.current_round && p.user_id === viewerId); const myDecision = decisions.find(d => d.user_id === viewerId);
  // A guess or a pass is spent per (round, target) now, not once per round
  // flat — the same player gets a fresh shot on every seat's own turn — so
  // "have I already acted this turn" has to be scoped to whoever currently
  // holds the turn, not to the round alone.
  const myGuess = guesses.find(g => g.round_number === board.current_round && g.target_user_id === board.active_user_id && g.user_id === viewerId);
  const myPass = passes.find(p => p.round_number === board.current_round && p.target_user_id === board.active_user_id && p.user_id === viewerId);
  const isActive = viewerId === board.active_user_id;
  const activePlayer = players.find(p => p.user_id === board.active_user_id);
  if (standings.length) return <Final standings={standings} players={players} tiebreaks={tiebreaks} />;
  const disabled = pending || isPaused;
  // Full-bleed, three columns — the same shape and DOM-order reasoning as
  // the auction's own live-play screen (see AuctionMatch's Screen): what's
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
        <div className="flex items-center gap-3">
          <p className="font-mono text-xs tracking-[.14em] text-fg-muted uppercase">
            {isActive ? (board.turn_deadline ? "Your pick" : board.x_factor_open ? "Your X-Factor" : "") : board.turn_deadline ? `Sabotage ${activePlayer?.display_name ?? "…"}` : board.x_factor_open ? `${activePlayer?.display_name ?? "…"}'s X-Factor` : "Locked"}
            {deadline ? ` · ${Math.max(0, Math.ceil((remainingMs ?? 0) / 1000))}s` : ""}
          </p>
          {isHost ? <PauseButton matchId={matchId} paused={isPaused} /> : null}
        </div>
      </header>
      <TurnStrip board={board} players={players} spins={spins} picks={picks} statuses={statuses} hits={hits} viewerId={viewerId} />
      {isPaused ? <PauseBanner /> : null}
      <div className="grid min-h-0 flex-1 gap-4 lg:grid-cols-[minmax(19rem,1fr)_minmax(20rem,1fr)_minmax(19rem,.95fr)] lg:grid-rows-1">
        <section className="flex min-h-0 flex-col gap-3 lg:col-start-1" aria-label="The turn">
          <TurnPanel board={board} players={players} spins={spins} guesses={guesses} passes={passes} hits={hits} viewerId={viewerId} />
        </section>
        <section className="flex min-h-0 flex-col gap-3 lg:col-start-2" aria-label="Your move">
          <AnimatedMessage role="alert" className="text-sm text-hidden-text">{error}</AnimatedMessage>
          {board.turn_deadline && isActive ? <PickForm options={options} mine={myPick} pending={disabled} onSubmit={(o) => call("submit_pick", { p_match_id: matchId, p_player_id: o.player_id, p_season: o.season })} /> : null}
          {board.turn_deadline && !isActive ? <GuessForm targetName={activePlayer?.display_name ?? "them"} status={myGuess ? "guessed" : myPass ? "passed" : "open"} pending={disabled} loadOptions={loadActiveOptions} onSubmit={(choice, exact, replacement) => call("submit_guess", { p_match_id: matchId, p_player_id: choice.player_id, p_season: exact ? choice.season : null, p_replacement_player_id: exact ? replacement?.player_id : null, p_replacement_season: exact ? replacement?.season : null })} onPass={() => call("submit_pass", { p_match_id: matchId })} /> : null}
          {board.x_factor_open && isActive ? <Decision mine={myDecision} pending={disabled} onSubmit={(slot) => call("submit_x_factor_decision", { p_match_id: matchId, p_replace_slot: slot })} /> : null}
          {board.x_factor_open && !isActive ? <Card edge={false}><CardTitle>{activePlayer?.display_name ?? "…"}&apos;s X-Factor</CardTitle><CardMeta>Waiting on their decision</CardMeta></Card> : null}
          {!board.turn_deadline && !board.x_factor_open ? <Card edge={false}><CardTitle>Between turns</CardTitle><CardMeta>Waiting on the next turn to open</CardMeta></Card> : null}
        </section>
        <aside className="min-h-0 overflow-y-auto lg:col-start-3" aria-label="Everyone's teams">
          <RosterBoard board={board} players={players} spins={spins} picks={picks} statuses={statuses} hits={hits} viewerId={viewerId} />
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
 */
function TurnPanel({ board, players, spins, guesses, passes, hits, viewerId }: { board: Board; players: Player[]; spins: Spin[]; guesses: Guess[]; passes: Pass[]; hits: Hit[]; viewerId: string }) {
  const activePlayer = players.find(p => p.user_id === board.active_user_id);
  const activeSpin = spins.find(s => s.round_number === board.current_round && s.user_id === board.active_user_id);
  const landedName = activeSpin ? franchiseName(activeSpin.franchise_code) : null;
  const others = players.filter(p => p.user_id !== board.active_user_id);

  const decoys = useMemo(() => shuffle(Object.values(FRANCHISE_NAMES).filter(name => name !== landedName)).slice(0, 7), [landedName]);
  const reelItems = landedName ? [...decoys, landedName] : [];
  // Keying the reel on the turn itself, not a separate effect-driven
  // counter, is what makes it replay automatically on every new turn: React
  // remounts (and so re-animates) whenever this key changes. `replayNonce`
  // only exists for the manual replay button, which has nothing to key off
  // of since the turn hasn't actually changed.
  const [replayNonce, setReplayNonce] = useState(0);
  const reelKey = `${board.current_round}-${board.active_user_id}-${replayNonce}`;

  // Fires once per (round, active seat) the moment that turn's hit count
  // grows — not on every refetch, which happens constantly from Realtime
  // traffic unrelated to this turn's outcome.
  const previousHitCount = useRef<Record<string, number>>({});
  const [flash, setFlash] = useState<{ kind: Hit["kind"] } | null>(null);
  useEffect(() => {
    const key = `${board.current_round}-${board.active_user_id}`;
    const turnHits = hits.filter(h => h.round_number === board.current_round && h.target_user_id === board.active_user_id);
    const previous = previousHitCount.current[key] ?? 0;
    previousHitCount.current[key] = turnHits.length;
    if (turnHits.length <= previous) return;
    setFlash({ kind: turnHits[turnHits.length - 1].kind });
    const timeout = setTimeout(() => setFlash(null), 1600);
    return () => clearTimeout(timeout);
  }, [hits, board.current_round, board.active_user_id]);

  return (
    <Card edge={false} className="flex flex-col">
      <div className="relative mx-3 mt-3 h-14 overflow-hidden bg-panel-fg" aria-hidden="true">
        <span className="pointer-events-none absolute inset-x-0 top-0 z-10 h-4 bg-gradient-to-b from-panel-fg to-transparent" />
        <span className="pointer-events-none absolute inset-x-0 bottom-0 z-10 h-4 bg-gradient-to-t from-panel-fg to-transparent" />
        {reelItems.length ? (
          <div key={reelKey} className="motion-safe:animate-reel-spin flex flex-col" style={{ "--reel-count": reelItems.length } as CSSProperties}>
            {reelItems.map((name, index) => (
              <span key={`${name}-${index}`} className="flex h-14 shrink-0 items-center justify-center font-slab text-lg tracking-[0.02em] text-panel uppercase">{name}</span>
            ))}
          </div>
        ) : (
          <p className="flex h-14 items-center justify-center font-mono text-xs text-panel-muted uppercase">Waiting on the next spin…</p>
        )}
      </div>
      <div className="px-3 pt-3 pb-1">
        <p className="font-slab text-2xl leading-none uppercase">{activePlayer?.display_name ?? "…"} is picking</p>
        <p className="mt-1 font-mono text-[11px] tracking-[0.11em] text-panel-muted uppercase">
          {landedName ? `Spun the ${landedName}` : "Spinning…"} · choosing {board.slot === "X_FACTOR" ? "any offensive skill player" : `a ${board.slot.replace(/[0-9]/g, "")}`}
        </p>
      </div>
      {reelItems.length ? (
        <button type="button" onClick={() => setReplayNonce(n => n + 1)} className="mx-3 mt-1 mb-1 self-start border border-panel-fg/25 px-2.5 py-1 font-mono text-[10px] tracking-[0.09em] text-panel-fg uppercase cursor-pointer hover:bg-panel-fg/5">
          ↻ Replay spin
        </button>
      ) : null}
      <div className="border-t border-dashed border-[#c7bfac] px-3 pt-2.5 pb-3">
        <p className="mb-2 font-mono text-[10px] tracking-[0.09em] text-panel-muted uppercase">This turn so far</p>
        <ul className="flex flex-col gap-1.5">
          {others.map(p => {
            const guessed = guesses.some(g => g.round_number === board.current_round && g.target_user_id === board.active_user_id && g.user_id === p.user_id);
            const passed = passes.some(pp => pp.round_number === board.current_round && pp.target_user_id === board.active_user_id && pp.user_id === p.user_id);
            return (
              <li key={p.user_id} className="flex items-center gap-2 text-sm">
                <span aria-hidden="true" className={`h-1.5 w-1.5 shrink-0 rounded-full ${guessed || passed ? "bg-panel-fg" : "border border-panel-muted"}`} />
                <span className="truncate font-semibold">{p.user_id === viewerId ? "You" : p.display_name}</span>
                <span className="ml-auto shrink-0 font-mono text-[10px] tracking-[0.07em] text-panel-muted uppercase">{guessed ? "Guessed" : passed ? "Passed" : "Hasn't acted"}</span>
              </li>
            );
          })}
        </ul>
      </div>
      <AnimatePresence>
        {flash ? (
          <motion.div key={flash.kind} initial={{ opacity: 0, scale: 0.94 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0 }} className="mx-3 mb-3 bg-hidden py-2.5 text-center font-slab text-xl tracking-[0.02em] text-panel uppercase">
            {flash.kind === "sabotage" ? "Sabotaged!" : "Respun!"}
          </motion.div>
        ) : null}
      </AnimatePresence>
    </Card>
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
    <ol aria-label="Draft order" className="flex shrink-0 gap-1.5 overflow-x-auto scroll-smooth pb-1 [scrollbar-width:thin]">
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
    </ol>
  );
}

const TURN_CELL = "h-[68px] shrink-0 rounded px-1.5 py-1";

function PastTurnCell({ round, slot, player, pick, locked, hits, mine }: { round: number; slot: string; player: Player; pick: Pick | null; locked: boolean; hits: Hit[]; mine: boolean }) {
  const respun = hits.some(h => h.kind === "respin");
  const sabotaged = hits.some(h => h.kind === "sabotage");
  const badge = respun && sabotaged ? "Respun · Sabotaged" : sabotaged ? "Sabotaged" : respun ? "Respun" : null;
  const outcome = mine && pick ? `${pick.display_name} · ${pick.season}` : locked ? "Locked" : "—";
  return (
    <li
      aria-label={`Round ${round}, ${player.display_name}, ${slot.replace("_", " ")}, ${outcome}${badge ? `, ${badge}` : ""}`}
      className={`${TURN_CELL} flex w-[76px] flex-col bg-surface-raised shadow-well`}
    >
      <p className="flex items-baseline justify-between gap-1 font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted uppercase">
        <span>{slot.replace("_", " ")}</span>
        <span className="tabular-nums">R{round}</span>
      </p>
      <p className="mt-1 truncate font-slab text-[11px] leading-none uppercase">{player.display_name}</p>
      <p className="mt-1 truncate font-mono text-[9px] leading-none tracking-[0.08em] text-fg-muted uppercase">{outcome}</p>
      {badge ? <p className="mt-1 truncate font-mono text-[8px] leading-none tracking-[0.08em] text-hidden-text uppercase">{badge}</p> : null}
    </li>
  );
}

function CurrentTurnCell({ round, slot, player, spin, ref }: { round: number; slot: string; player: Player; spin: Spin | null; ref?: Ref<HTMLLIElement> }) {
  return (
    <li ref={ref} aria-current="step" className={`${TURN_CELL} flex w-[140px] flex-col justify-center border border-panel/45 bg-panel/10 px-2.5`}>
      <p className="font-slab text-sm leading-none uppercase">
        R{round} <span className="font-mono text-[10px] tracking-[0.1em] text-fg-muted">· {slot.replace("_", " ")}</span>
      </p>
      <p className="mt-1 truncate font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{player.display_name} on the clock</p>
      {spin ? <p className="truncate font-mono text-[9px] tracking-[0.08em] text-fg-muted uppercase">{franchiseName(spin.franchise_code)}</p> : null}
    </li>
  );
}

function FutureTurnCell({ round, slot, player, spin }: { round: number; slot: string; player: Player; spin: Spin | null }) {
  return (
    <li
      aria-label={`Round ${round}, ${player.display_name}, ${slot.replace("_", " ")}, not yet drafted`}
      className={`${TURN_CELL} flex w-[76px] flex-col items-center justify-center gap-0.5 border border-dashed border-line bg-transparent px-1`}
    >
      <p className="font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted uppercase">R{round} · {slot.replace("_", " ")}</p>
      <p className="truncate font-mono text-[9px] leading-none text-fg-muted uppercase">{player.display_name}</p>
      {spin ? <p className="truncate font-mono text-[8px] leading-none tracking-[0.08em] text-fg-muted/70 uppercase">{franchiseName(spin.franchise_code)}</p> : null}
    </li>
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
function RosterBoard({ board, players, spins, picks, statuses, hits, viewerId }: { board: Board; players: Player[]; spins: Spin[]; picks: Pick[]; statuses: PickStatus[]; hits: Hit[]; viewerId: string }) {
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

        return (
          <details key={player.user_id} open={mine}>
            <summary className="grid cursor-pointer grid-cols-[1.85rem_1fr_auto_1rem] items-center gap-2.5 px-3 py-2.5 hover:bg-panel/5">
              <span aria-hidden="true" className={`flex h-7 w-7 items-center justify-center font-slab text-base ${mine ? "bg-hidden text-panel" : "bg-surface text-fg"}`}>
                {player.display_name.slice(0, 1).toUpperCase()}
              </span>
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
              <span className="whitespace-nowrap font-mono text-[9px] tracking-[0.06em] text-fg-muted uppercase">
                {hitCount ? <span className="text-hidden-text">{hitCount} hit{hitCount === 1 ? "" : "s"}</span> : "No hits"}
              </span>
              <span aria-hidden="true" className="roster-chev text-[11px] text-fg-muted transition-transform">▸</span>
            </summary>
            <div className="px-2.5 pb-2.5">
              <div className="divide-y divide-[rgb(23_21_15_/_0.06)] bg-panel text-panel-fg">
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
                  return (
                    <div key={round} className="grid grid-cols-[4.4rem_1fr] items-center gap-2 px-2.5 py-1.5">
                      <span className="font-mono text-[10px] tracking-[0.07em] text-panel-muted uppercase">{slot.replace("_", " ")} · R{round}</span>
                      <span className="flex min-w-0 items-center gap-1.5 text-[12px]">
                        {filled && mine ? (
                          <span className="truncate font-semibold">{pick ? `${pick.display_name} · ${pick.season}` : "Locked"}</span>
                        ) : filled ? (
                          <Concealed label={`${player.display_name}'s concealed pick`} className="inline-block shrink-0 px-1.5 py-0.5 font-mono text-[9px] tracking-[0.06em] uppercase">
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
type Tenured = { player_id: string; display_name: string; seasons: number[] };

function groupByPlayer(options: Option[]): Tenured[] {
  const map = new Map<string, Tenured>();
  for (const o of options) {
    const existing = map.get(o.player_id);
    if (existing) existing.seasons.push(o.season);
    else map.set(o.player_id, { player_id: o.player_id, display_name: o.display_name, seasons: [o.season] });
  }
  return [...map.values()].map(g => ({ ...g, seasons: [...g.seasons].sort((a, b) => b - a) }));
}

/**
 * A flat dropdown of every player this franchise/slot has ever fielded is a
 * wall for a team with decades of history at a slot. The three most tenured
 * players at the top are a one-tap shortcut for the read most people
 * actually have ("who played this position here the longest"); the search
 * field underneath is the escape hatch for anyone else.
 *
 * `needsSeason` is false for a name-only guess, where the game itself never
 * checks the year — picking a player is the whole decision. It's true for a
 * pick and for an exact guess, where a specific season is part of what's
 * being claimed; choosing a player then reveals a row of that player's own
 * seasons to finish the selection.
 */
function PlayerPicker({ options, needsSeason, value, onChange, pending }: { options: Option[]; needsSeason: boolean; value: Option | null; onChange: (option: Option | null) => void; pending: boolean }) {
  const grouped = useMemo(() => groupByPlayer(options), [options]);
  const tenured = useMemo(() => [...grouped].sort((a, b) => b.seasons.length - a.seasons.length || b.seasons[0] - a.seasons[0]).slice(0, 3), [grouped]);
  const [query, setQuery] = useState("");
  const [pendingPlayer, setPendingPlayer] = useState<Tenured | null>(null);
  const results = query.trim() ? grouped.filter(g => g.display_name.toLowerCase().includes(query.trim().toLowerCase())).slice(0, 8) : [];

  const choosePlayer = (g: Tenured) => {
    if (!needsSeason) { onChange({ player_id: g.player_id, display_name: g.display_name, season: g.seasons[0], slot_category: options.find(o => o.player_id === g.player_id)?.slot_category ?? "" }); return; }
    setPendingPlayer(g);
  };
  const chooseSeason = (g: Tenured, season: number) => {
    onChange({ player_id: g.player_id, display_name: g.display_name, season, slot_category: options.find(o => o.player_id === g.player_id && o.season === season)?.slot_category ?? "" });
    setPendingPlayer(null);
  };

  if (value) {
    return (
      <div className="flex items-center justify-between gap-2 bg-surface-raised px-3 py-2.5 text-sm text-fg">
        <span><span className="font-semibold">{value.display_name}</span> <span className="font-mono text-xs text-fg-muted">· {value.season}</span></span>
        <button type="button" disabled={pending} onClick={() => { onChange(null); setPendingPlayer(null); }} className="cursor-pointer font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase underline underline-offset-2">Change</button>
      </div>
    );
  }

  if (pendingPlayer) {
    return (
      <div className="flex flex-col gap-2">
        <p className="font-mono text-xs tracking-[0.08em] text-panel-muted uppercase">{pendingPlayer.display_name} — choose a year</p>
        <div className="flex flex-wrap gap-1.5">
          {pendingPlayer.seasons.map(season => (
            <button key={season} type="button" disabled={pending} onClick={() => chooseSeason(pendingPlayer, season)} className="cursor-pointer bg-surface-raised px-2.5 py-1 font-mono text-xs text-fg tabular-nums hover:bg-white/5">{season}</button>
          ))}
        </div>
        <button type="button" onClick={() => setPendingPlayer(null)} className="cursor-pointer self-start font-mono text-[10px] tracking-[0.08em] text-panel-muted uppercase underline underline-offset-2">Back</button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {tenured.length ? (
        <div className="grid grid-cols-3 gap-1.5">
          {tenured.map(g => (
            <button key={g.player_id} type="button" disabled={pending} onClick={() => choosePlayer(g)} className="flex cursor-pointer flex-col gap-0.5 border border-line bg-surface-raised px-2 py-1.5 text-left hover:border-hidden-text">
              <span className="font-mono text-[9px] tracking-[0.06em] text-hidden-text uppercase">{g.seasons.length} season{g.seasons.length === 1 ? "" : "s"}</span>
              <span className="truncate text-xs font-semibold text-fg">{g.display_name}</span>
            </button>
          ))}
        </div>
      ) : null}
      <input
        type="text"
        aria-label="Search a player"
        placeholder="Search a name…"
        value={query}
        onChange={e => setQuery(e.target.value)}
        className="bg-surface-raised px-3 py-2 text-sm text-fg placeholder:text-fg-muted"
      />
      {results.length ? (
        <ul className="max-h-36 overflow-y-auto border border-line bg-surface-raised">
          {results.map(g => (
            <li key={g.player_id}>
              <button type="button" disabled={pending} onClick={() => choosePlayer(g)} className="flex w-full cursor-pointer items-center justify-between px-3 py-1.5 text-left text-sm text-fg hover:bg-white/5">
                <span className="truncate">{g.display_name}</span>
                <span className="shrink-0 font-mono text-[10px] text-fg-muted">{g.seasons[g.seasons.length - 1]}–{g.seasons[0]}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

function PickForm({ options, mine, pending, onSubmit }: { options: Option[]; mine?: Pick; pending: boolean; onSubmit: (o: Option) => void }) {
  const [option, setOption] = useState<Option | null>(null);
  if (mine) return <Card><CardTitle>Your pick is locked</CardTitle><CardMeta>{mine.display_name} · {mine.season} · waiting on the rest of the table</CardMeta></Card>;
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
  const [options, setOptions] = useState<Option[]>([]); const [guess, setGuess] = useState<Option | null>(null); const [exact, setExact] = useState(false); const [replacement, setReplacement] = useState<Option | null>(null);
  useEffect(() => { let cancelled = false; void loadOptions().then(o => { if (!cancelled) setOptions(o); }); return () => { cancelled = true; }; }, [loadOptions]);
  // Adjusted during render rather than in an effect (React's own pattern for
  // resetting state when a prop/toggle changes — see "You Might Not Need an
  // Effect"): a player chosen while name-only carries an unused, arbitrary
  // season, and letting that stale season ride into an exact guess would
  // silently guess the wrong year instead of the one the toggle now demands.
  const [exactAtLastGuess, setExactAtLastGuess] = useState(exact);
  if (exact !== exactAtLastGuess) { setExactAtLastGuess(exact); setGuess(null); }
  if (status !== "open") return <Card><CardTitle>{status === "passed" ? "You passed on this turn" : "Guess spent on this turn"}</CardTitle><CardMeta>Waiting on the rest of the table</CardMeta></Card>;
  return (
    <Card>
      <CardTitle>Sabotage {targetName}&apos;s pick</CardTitle>
      <div className="flex flex-col gap-3 p-3 pt-0">
        <PlayerPicker options={options} needsSeason={exact} value={guess} onChange={setGuess} pending={pending} />
        <label className="flex items-center gap-2 text-sm"><input className="h-4 w-4" type="checkbox" checked={exact} onChange={e => setExact(e.target.checked)} />Exact player and year — choose a replacement if right</label>
        {exact ? (
          <div className="flex flex-col gap-1.5">
            <p className="font-mono text-[10px] tracking-[0.08em] text-panel-muted uppercase">Replacement if you&apos;re right</p>
            <PlayerPicker options={options} needsSeason value={replacement} onChange={setReplacement} pending={pending} />
          </div>
        ) : null}
        <div className="flex gap-2">
          <Button className="flex-1" disabled={!guess || (exact && !replacement) || pending} onClick={() => guess && onSubmit(guess, exact, replacement ?? undefined)}>Submit one guess</Button>
          <Button variant="ink" disabled={pending} onClick={onPass}>Pass</Button>
        </div>
      </div>
    </Card>
  );
}
function Decision({ mine, pending, onSubmit }: { mine?: Decision; pending: boolean; onSubmit: (slot: string | null) => void }) { if (mine) return <Card><CardTitle>X-Factor decision locked</CardTitle><CardMeta>{mine.replace_slot ? `Replaces ${mine.replace_slot}` : "Discarded"}</CardMeta></Card>; return <Card><CardTitle>Assign or discard your X-Factor</CardTitle><div className="grid grid-cols-2 gap-2 p-3 pt-0">{skillSlots.map(slot => <Button key={slot} variant="ink" disabled={pending} onClick={() => onSubmit(slot)}>Replace {slot}</Button>)}<Button className="col-span-2" disabled={pending} onClick={() => onSubmit(null)}>Discard X-Factor</Button></div></Card>; }
function Final({ standings, players, tiebreaks }: { standings: Standing[]; players: Player[]; tiebreaks: Tiebreak[] }) { const name = (id: string) => players.find(p => p.user_id === id)?.display_name ?? "Unknown"; return <main className="mx-auto flex w-full max-w-md flex-1 flex-col gap-4 px-4 py-8"><Card><CardTitle>Final standings</CardTitle><ol className="p-3 pt-0">{[...standings].sort((a,b) => b.wins-a.wins || a.tiebreak_rank-b.tiebreak_rank).map((s, index) => <motion.li key={s.user_id} variants={staggerRow(index)} initial="initial" animate="animate" className="border-t border-panel-shade py-2 text-sm">#{s.tiebreak_rank} {name(s.user_id)} · {s.wins}-{s.losses} · {s.roster_strength} AV</motion.li>)}</ol></Card>{tiebreaks.length ? <Card><CardTitle>Tiebreak bracket</CardTitle><div className="p-3 pt-0 text-sm">{tiebreaks.map(g => <p key={`${g.record_wins}-${g.bracket_round}-${g.game_number}`} className="border-t border-panel-shade py-2">{g.player_b ? `${name(g.player_a)} vs ${name(g.player_b)}` : `${name(g.player_a)} bye`} → {name(g.winner_user_id)}</p>)}</div></Card> : null}</main>; }
