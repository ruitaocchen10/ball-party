"use client";

import { useCallback, useEffect, useRef, useState, type Ref } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import {
  abbreviate, MatchStrip, StripCell, StripCellAvatar, StripCellCaption, StripCellName,
  StripCellTextColumn, StripCellTitle, StripCellTop,
} from "@/components/foundation/ui-kit/MatchStrip";
import { PostGameControls } from "@/components/runtime/game-runtime/PostGameControls";
import { PostGameNavigation } from "@/components/runtime/game-runtime/PostGameNavigation";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";
import { createClient } from "@/lib/supabase/client";
import { HEARTBEAT_MS, VISIBLE_SLACK_MS, useMatchClock } from "@/lib/runtime/game-runtime/useMatchClock";
import {
  boardFromState, CLUE_MAX_CHARS, CLUE_MAX_WORDS, DIAL, dialPoint, dialPosition, scoringWedges, type Board,
  type Card, type Clue, type ClueStatus, type Target, type WavelengthPlayer, type WavelengthResult, type WavelengthRound,
  validateClue,
} from "@/lib/games/wavelength/board";

type Initial = { board: Board; players: WavelengthPlayer[]; rounds: WavelengthRound[]; cards: Card[]; clues: Clue[]; clueStatuses: ClueStatus[]; result: WavelengthResult | null };
const NEEDLE_BROADCAST_INTERVAL_MS = 100; // At most 10 position updates per second.
const NEEDLE_REPORT_INTERVAL_MS = 1000; // The server only needs the needle for auto-lock, so report it lazily.
const REVEAL_MS = 5000; // How long a locked round's result stays on screen above the next round.

type NeedleBroadcast = { round: number; position: number };

function isNeedleBroadcast(value: unknown): value is NeedleBroadcast {
  if (!value || typeof value !== "object") return false;
  const { round, position } = value as Record<string, unknown>;
  return Number.isInteger(round) && typeof position === "number" && Number.isInteger(position) && position >= 0 && position <= 1000;
}

/** Wavelength only renders values that the database has already permitted the
 * viewer to read. In particular, target rows are never fetched here. */
export function WavelengthMatch({ matchId, viewerId, roomCode, isHost, paused = false, initial }: {
  matchId: string; viewerId: string; roomCode: string | null; isHost: boolean; paused?: boolean; initial: Initial;
}) {
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);
  const [board, setBoard] = useState(initial.board);
  const [players, setPlayers] = useState(initial.players);
  const [rounds, setRounds] = useState(initial.rounds);
  const [cards, setCards] = useState(initial.cards);
  const [clues, setClues] = useState(initial.clues);
  const [statuses, setStatuses] = useState(initial.clueStatuses);
  const [result, setResult] = useState(initial.result);
  const [isPaused, setIsPaused] = useState(paused);
  const [clue, setClue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [needle, setNeedle] = useState(500);
  const [locking, setLocking] = useState(false);
  const [needleRound, setNeedleRound] = useState(initial.board.currentRound);
  if (needleRound !== board.currentRound) { setNeedleRound(board.currentRound); setNeedle(500); setError(null); }
  const [targets, setTargets] = useState<Target[]>([]);
  const [revealRound, setRevealRound] = useState<number | null>(null);
  const settledRounds = useRef(new Set(initial.rounds.filter((round) => round.status === "locked" || round.status === "skipped").map((round) => round.round)));
  const reportTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestNeedle = useRef(500);
  const needleChannel = useRef<ReturnType<ReturnType<typeof createClient>["channel"]> | null>(null);
  const needleChannelReady = useRef(false);
  const lastNeedleBroadcastAt = useRef(0);
  const needleView = useRef({ phase: initial.board.phase, round: initial.board.currentRound, guesserId: null as string | null });

  const applyBoard = useCallback((value: unknown) => { const parsed = boardFromState(value); if (parsed) setBoard(parsed); }, []);
  const refetch = useCallback(async () => {
    const supabase = getClient();
    const [state, playerRows, roundRows, cardRows, clueRows, statusRows, resultRow, targetRows] = await Promise.all([
      supabase.schema("wavelength" as never).rpc("state" as never, { p_match_id: matchId } as never),
      supabase.from("wavelength_players").select("*, profiles(display_name, avatar_url)").eq("match_id", matchId).order("seat"),
      supabase.from("wavelength_rounds").select("*").eq("match_id", matchId).order("round"),
      supabase.from("wavelength_cards").select("*").eq("match_id", matchId).order("round"),
      supabase.from("wavelength_clues" as never).select("*").eq("match_id", matchId).order("round"),
      supabase.from("wavelength_clue_statuses").select("*").eq("match_id", matchId),
      supabase.from("wavelength_results").select("*").eq("match_id", matchId).maybeSingle(),
      // Row-level security returns only the targets the viewer is the psychic for.
      supabase.from("wavelength_targets").select("*").eq("match_id", matchId),
    ]);
    applyBoard(state.data);
    if (playerRows.data) setPlayers(playerRows.data.map(({ profiles, ...player }: { profiles?: { display_name?: string | null; avatar_url?: string | null }; [key: string]: unknown }) => ({ ...player, display_name: profiles?.display_name ?? "Unknown player", avatar_url: profiles?.avatar_url ?? null })) as unknown as WavelengthPlayer[]);
    if (roundRows.data) setRounds(roundRows.data as WavelengthRound[]);
    if (cardRows.data) setCards(cardRows.data as Card[]);
    if (clueRows.data) setClues(clueRows.data as Clue[]);
    if (statusRows.data) setStatuses(statusRows.data as ClueStatus[]);
    if (resultRow.data) setResult(resultRow.data as WavelengthResult);
    if (targetRows.data) setTargets(targetRows.data as Target[]);
  }, [applyBoard, getClient, matchId]);

  const { remainingMs, reconcile } = useMatchClock({
    serverNow: board.serverNow, deadline: board.phase === "complete" ? null : board.phaseDeadline,
    visibleSlackMs: board.phase === "guess" ? VISIBLE_SLACK_MS : 0,
    heartbeatMs: HEARTBEAT_MS, paused: isPaused,
    expire: () => getClient().schema("wavelength" as never).rpc("tick" as never, { p_match_id: matchId } as never).then(({ data }: { data: unknown }) => applyBoard(data)),
    reconcile: refetch,
  });

  useEffect(() => {
    let cancelled = false; let cleanup: (() => void) | undefined;
    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;
      const channel = supabase.channel(`wavelength:${matchId}`, { config: { private: true } })
        .on("broadcast", { event: "needle" }, (event: { payload: unknown }) => {
          const update = event.payload;
          const view = needleView.current;
          // The guesser already has their pointer's exact local value. Never
          // replace it with a round-trip broadcast, even if the server echoes.
          if (view.phase === "guess" && view.guesserId !== viewerId && update && isNeedleBroadcast(update) && update.round === view.round) setNeedle(update.position);
        })
        .on("postgres_changes", { event: "*", schema: "public", table: "wavelength_matches", filter: `match_id=eq.${matchId}` }, () => { void refetch(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "wavelength_rounds", filter: `match_id=eq.${matchId}` }, () => { void refetch(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "wavelength_players", filter: `match_id=eq.${matchId}` }, () => { void refetch(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "wavelength_clue_statuses", filter: `match_id=eq.${matchId}` }, () => { void refetch(); })
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${matchId}` }, (payload) => setIsPaused((payload.new as { status?: string }).status === "paused"))
        .subscribe((status) => {
          needleChannelReady.current = status === "SUBSCRIBED";
          if (status === "SUBSCRIBED") reconcile();
        });
      needleChannel.current = channel;
      cleanup = () => {
        needleChannelReady.current = false;
        if (needleChannel.current === channel) needleChannel.current = null;
        void supabase.removeChannel(channel);
      };
    })();
    return () => { cancelled = true; cleanup?.(); };
  }, [matchId, reconcile, refetch, viewerId]);

  const current = rounds.find((round) => round.round === board.currentRound) ?? null;
  const currentCard = cards.find((card) => card.round === board.currentRound) ?? null;
  // Fill is parallel: currentRound is the first round that will be guessed,
  // not necessarily this psychic's card. A psychic may own several rounds, and
  // a written round stays pending until it is guessed, so the one to write next
  // is their first pending round without a clue status.
  const hasClue = (round: number) => statuses.some((status) => status.round === round);
  const myFillRound = rounds.find((round) => round.psychic_id === viewerId && round.status === "pending" && !hasClue(round.round)) ?? null;
  const myFillTotal = rounds.filter((round) => round.psychic_id === viewerId && round.status === "pending").length;
  const myFillWritten = rounds.filter((round) => round.psychic_id === viewerId && round.status === "pending" && hasClue(round.round)).length;
  const myFillCard = myFillRound ? cards.find((card) => card.round === myFillRound.round) ?? null : null;
  const myFillTarget = myFillRound ? targets.find((target) => target.round === myFillRound.round)?.target ?? null : null;
  const canFill = !!myFillRound && !!myFillCard;
  const currentClue = clues.find((item) => item.round === board.currentRound)?.clue ?? null;
  const currentTarget = targets.find((target) => target.round === board.currentRound)?.target ?? null;
  const isPsychic = current?.psychic_id === viewerId;
  const isGuesser = current?.guesser_id === viewerId;
  const time = remainingMs === null ? null : `${Math.ceil(remainingMs / 1000)}s`;

  useEffect(() => {
    needleView.current = { phase: board.phase, round: board.currentRound, guesserId: current?.guesser_id ?? null };
  }, [board.currentRound, board.phase, current?.guesser_id]);

  // A round that just settled is shown to everyone for a few seconds, above
  // whatever the table has already moved on to. Rounds already settled when
  // the screen mounted (or when we rejoin) are not replayed.
  useEffect(() => {
    const fresh = rounds.filter((round) => (round.status === "locked" || round.status === "skipped") && !settledRounds.current.has(round.round));
    if (fresh.length === 0) return;
    fresh.forEach((round) => settledRounds.current.add(round.round));
    setRevealRound(Math.max(...fresh.map((round) => round.round)));
    const timer = setTimeout(() => setRevealRound(null), REVEAL_MS);
    return () => clearTimeout(timer);
  }, [rounds]);

  // Every round starts from the middle of the dial.
  useEffect(() => {
    latestNeedle.current = 500;
    if (reportTimer.current) { clearTimeout(reportTimer.current); reportTimer.current = null; }
  }, [board.currentRound]);
  useEffect(() => () => { if (reportTimer.current) clearTimeout(reportTimer.current); }, []);

  const moveNeedle = (position: number) => {
    setNeedle(position);
    if (board.phase !== "guess" || !isGuesser || locking) return;
    latestNeedle.current = position;
    // Tell the server where the needle sits so an auto-lock lands there. Lazy
    // and best-effort: lock_guess carries the authoritative position.
    if (!reportTimer.current) {
      const round = current?.round;
      reportTimer.current = setTimeout(() => {
        reportTimer.current = null;
        if (round != null) void getClient().schema("wavelength").rpc("report_needle", { p_match_id: matchId, p_round: round, p_position: latestNeedle.current });
      }, NEEDLE_REPORT_INTERVAL_MS);
    }
    if (!needleChannelReady.current) return;
    const now = Date.now();
    if (now - lastNeedleBroadcastAt.current < NEEDLE_BROADCAST_INTERVAL_MS) return;
    lastNeedleBroadcastAt.current = now;
    // Broadcast is deliberately best-effort: lock_guess is the only mutation
    // and scoring source, so a missing/slow socket must never block the game.
    void needleChannel.current?.send({ type: "broadcast", event: "needle", payload: { round: current?.round, position } });
  };

  const submitClue = async (event: React.FormEvent) => {
    event.preventDefault();
    const message = validateClue(clue);
    if (message || !myFillRound) { setError(message); return; }
    setSaving(true); setError(null);
    const { data, error: rpcError } = await getClient().schema("wavelength" as never).rpc("submit_clue" as never, { p_match_id: matchId, p_round: myFillRound.round, p_clue: clue.trim() } as never);
    setSaving(false);
    if (rpcError) { setError(CLUE_MESSAGES[rpcError.message] ?? rpcError.message); return; }
    applyBoard(data); setClue(""); await refetch();
  };
  const lockGuess = async () => {
    if (!current) return;
    // `locking` stops moveNeedle publishing a movement that races with the lock.
    setLocking(true); setError(null);
    const { data, error: rpcError } = await getClient().schema("wavelength" as never).rpc("lock_guess" as never, { p_match_id: matchId, p_round: current.round, p_position: needle } as never);
    setLocking(false);
    if (reportTimer.current) { clearTimeout(reportTimer.current); reportTimer.current = null; }
    if (rpcError) { setError(rpcError.message); return; }
    applyBoard(data); await refetch();
  };

  if (board.phase === "complete") {
    return (
      <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-6 px-5 py-8 text-fg">
        <header className="border-b border-line pb-4">
          <p className="font-slab text-xs uppercase tracking-[.18em] text-fg-muted">Wavelength</p>
          <h1 className="font-slab text-2xl">{board.mode === "coop" ? "Co-op" : "Team versus"}</h1>
        </header>
        {result && <ResultScreen result={result} scores={board.teamScores} roundCount={board.roundCount} rounds={rounds} />}
        {roomCode && <><PostGameNavigation matchId={matchId} roomCode={roomCode} /><PostGameControls matchId={matchId} roomCode={roomCode} isHost={isHost} /></>}
      </main>
    );
  }

  return (
    <main className="mx-auto flex w-full min-h-0 flex-1 flex-col gap-3 overflow-hidden px-4 pt-3 pb-4">
      <header className="flex items-baseline justify-between">
        <div>
          <p className="font-slab text-xs uppercase tracking-[.18em] text-fg-muted">Wavelength</p>
          <h1 className="font-slab text-2xl leading-none">{board.mode === "coop" ? "Co-op" : "Team versus"}</h1>
        </div>
        <p aria-label="Countdown" className="font-slab text-lg tabular-nums">{isPaused ? "Paused" : time ?? ""}</p>
      </header>

      <RoundStrip board={board} rounds={rounds} players={players} />

      {/* DOM order is the phone's decision order: see the board, decide what
          to do, then check everyone else — the same order Auction uses. */}
      <div className="grid min-h-0 flex-1 grid-rows-[auto_auto_minmax(6rem,1fr)] gap-3 lg:grid-cols-[minmax(15rem,.62fr)_minmax(0,1fr)_minmax(21rem,.95fr)] lg:grid-rows-1">

        <section className="relative flex min-h-0 flex-1 flex-col lg:col-start-2 lg:row-start-1" aria-label="The board">
          {revealRound != null && board.phase !== "reveal" && (
            <RevealBanner round={rounds.find((round) => round.round === revealRound) ?? null} scores={board.teamScores} />
          )}
          {board.phase === "fill" && (
            canFill
              ? <BoardPanel card={myFillCard} target={myFillTarget ?? undefined} caption="Only you can see the target" />
              : <div className="flex flex-1 items-center justify-center bg-panel p-6 text-center text-sm text-panel-muted shadow-card">Everyone fills out their own cards in private.</div>
          )}
          {board.phase === "guess" && (
            <BoardPanel card={currentCard} clue={currentClue} target={isPsychic ? currentTarget : null} needle={needle} setNeedle={moveNeedle} interactive={isGuesser && !locking} />
          )}
          {board.phase === "reveal" && current && (
            <BoardPanel card={currentCard} clue={currentClue} target={current.revealed_target} needle={current.guess_position ?? undefined} points={current.points} skipped={current.status === "skipped"} />
          )}
        </section>

        <section className="flex min-h-0 flex-col gap-3 lg:col-start-1 lg:row-start-1" aria-label="Controls">
          {board.phase === "fill" && (
            <FillControls canFill={canFill} myFillWritten={myFillWritten} myFillTotal={myFillTotal} clue={clue} error={error} saving={saving} onChange={setClue} onSubmit={submitClue} />
          )}
          {board.phase === "guess" && (
            <GuessControls isGuesser={isGuesser} isPsychic={isPsychic} locking={locking} error={error} onLock={lockGuess} hasCard={!!currentCard} />
          )}
          {board.phase === "reveal" && <RevealControls round={current} />}
        </section>

        <aside className="min-h-0 overflow-y-auto lg:col-start-3 lg:row-start-1" aria-label="The table">
          <TablePanel players={players} board={board} rounds={rounds} statuses={statuses} current={current} viewerId={viewerId} />
        </aside>
      </div>
    </main>
  );
}

/** The top bar: every round this match will play, settled ones carrying what
 * they scored, the current one naming its psychic, the rest just numbered. */
function RoundStrip({ board, rounds, players }: { board: Board; rounds: WavelengthRound[]; players: WavelengthPlayer[] }) {
  const current = useRef<HTMLLIElement>(null);
  useEffect(() => {
    current.current?.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" });
  }, [board.currentRound]);
  return (
    <MatchStrip ariaLabel="Round strip">
      {rounds.map((round) =>
        round.round === board.currentRound ? (
          <CurrentRoundCell key={round.round} ref={current} board={board} round={round} players={players} />
        ) : round.status === "locked" || round.status === "skipped" ? (
          <SettledRoundCell key={round.round} round={round} players={players} />
        ) : (
          <UpcomingRoundCell key={round.round} roundNumber={round.round} />
        ),
      )}
    </MatchStrip>
  );
}

function SettledRoundCell({ round, players }: { round: WavelengthRound; players: WavelengthPlayer[] }) {
  const psychicName = players.find((player) => player.user_id === round.psychic_id)?.display_name ?? "Unknown player";
  const guesserName = players.find((player) => player.user_id === round.guesser_id)?.display_name ?? "";
  const scoreLabel = round.status === "skipped" ? "skipped" : `${round.points ?? 0} points`;
  return (
    <StripCell tone="settled" width={92} ariaLabel={`Round ${round.round}, ${psychicName}'s clue, ${scoreLabel}`}>
      <StripCellTop left={`R${round.round}`} right={round.status === "skipped" ? "skip" : `${round.points ?? 0}pt`} />
      <StripCellAvatar name={psychicName} />
      <StripCellName center>{abbreviate(psychicName)}</StripCellName>
      <StripCellCaption center>{guesserName}</StripCellCaption>
    </StripCell>
  );
}

function CurrentRoundCell({ board, round, players, ref }: { board: Board; round: WavelengthRound; players: WavelengthPlayer[]; ref?: Ref<HTMLLIElement> }) {
  const psychic = players.find((player) => player.user_id === round.psychic_id) ?? null;
  return (
    <StripCell tone="current" width={176} ref={ref}>
      {psychic ? <StripCellAvatar name={psychic.display_name} big /> : null}
      <StripCellTextColumn>
        <StripCellTitle meta={`/ ${board.roundCount}`}>Round {round.round}</StripCellTitle>
        <StripCellCaption>{board.phase === "fill" ? "Writing clues" : board.phase === "guess" ? "Guessing" : "Revealed"}</StripCellCaption>
        {psychic ? <StripCellCaption>{psychic.display_name}&apos;s clue</StripCellCaption> : null}
      </StripCellTextColumn>
    </StripCell>
  );
}

function UpcomingRoundCell({ roundNumber }: { roundNumber: number }) {
  return (
    <StripCell tone="upcoming" width={92} ariaLabel={`Round ${roundNumber}, not yet played`} className="gap-2">
      <span aria-hidden className="mx-auto block h-7 w-7 rounded-full border border-dashed border-line" />
      <span className="text-center font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted tabular-nums">{roundNumber}</span>
    </StripCell>
  );
}

/** A non-blocking flash for a round that just settled while the table has
 * already moved on to the next one underneath it (see the REVEAL_MS effect
 * above) — it never covers the live board's controls. */
function RevealBanner({ round, scores }: { round: WavelengthRound | null; scores: number[] }) {
  if (!round) return null;
  const skipped = round.status === "skipped";
  const reaction = skipped ? "Clue skipped" : round.points === 4 ? "Bullseye!" : round.points === 3 ? "So close!" : round.points === 2 ? "In the zone" : "Off the mark";
  return (
    <div role="status" className="animate-sold-headline absolute inset-x-3 top-3 z-10 flex items-center gap-4 border border-panel-fg/15 bg-panel px-4 py-3 text-panel-fg shadow-card">
      {!skipped && (
        <div className="w-28 shrink-0">
          <Dial needle={round.guess_position ?? undefined} target={round.revealed_target ?? undefined} label={`Round ${round.round} result`} />
        </div>
      )}
      <div className="min-w-0 flex-1">
        <p className="truncate font-slab text-lg leading-none">{skipped ? reaction : `${reaction} · ${round.points ?? 0} points`}</p>
        <p className="mt-1 font-mono text-[11px] uppercase tracking-[.1em] text-panel-muted">Round {round.round} · running score {scores.join(" – ")}</p>
      </div>
    </div>
  );
}

/** The board, in all three live phases: the spectrum's endpoints and the
 * dial, plus whichever of a clue or a score goes with the moment. */
function BoardPanel({ card, clue, target, needle, setNeedle, interactive, points, skipped, caption }: {
  card: Card | null;
  clue?: string | null;
  target?: number | null;
  needle?: number;
  setNeedle?: (position: number) => void;
  interactive?: boolean;
  points?: number | null;
  skipped?: boolean;
  caption?: string;
}) {
  return (
    <div className="flex flex-1 items-center justify-center bg-panel px-6 py-6 text-panel-fg shadow-card">
      <div className="flex w-full max-w-xl flex-col items-center gap-3.5">
        {clue !== undefined && (
          <div className="text-center">
            <p className="font-mono text-[11px] uppercase tracking-[.14em] text-panel-muted">The clue</p>
            <p className="font-slab text-4xl leading-none">&ldquo;{clue ?? "Waiting for the clue…"}&rdquo;</p>
          </div>
        )}
        {caption && <p className="text-center font-mono text-[11px] uppercase tracking-[.14em] text-panel-muted">{caption}</p>}
        {card && <Endpoints card={card} />}
        {card && <Dial needle={needle} setNeedle={setNeedle} target={target ?? undefined} interactive={!!interactive} />}
        {points !== undefined && <p className="font-slab text-2xl">{skipped ? "Clue skipped" : `${points ?? 0} points`}</p>}
      </div>
    </div>
  );
}

function FillControls({ canFill, myFillWritten, myFillTotal, clue, error, saving, onChange, onSubmit }: {
  canFill: boolean; myFillWritten: number; myFillTotal: number; clue: string; error: string | null; saving: boolean;
  onChange: (value: string) => void; onSubmit: (event: React.FormEvent) => void;
}) {
  if (!canFill) {
    return (
      <div className="flex flex-1 flex-col justify-center gap-2 bg-surface-raised p-5 text-sm text-fg-muted shadow-well">
        <p className="font-mono text-[10px] uppercase tracking-[.12em] text-fg-muted">Your move</p>
        <p>{myFillTotal > 0 && myFillWritten === myFillTotal ? "Your clues are written. Waiting for the others." : "Your teammate is writing the clues."}</p>
      </div>
    );
  }
  return (
    <form onSubmit={onSubmit} className="flex flex-1 flex-col gap-3 bg-surface-raised p-5 shadow-well">
      <div>
        <p className="font-mono text-[10px] uppercase tracking-[.12em] text-fg-muted">Your move</p>
        <p className="font-slab text-xl">Write your clue{myFillTotal > 1 ? ` (${myFillWritten + 1} of ${myFillTotal})` : ""}</p>
        <p className="mt-1 text-sm text-fg-muted">One shot, aimed at the hidden target only you can see.</p>
      </div>
      <label className="grid gap-1 text-sm font-medium">
        Clue
        <textarea aria-label="Clue" value={clue} maxLength={CLUE_MAX_CHARS + 1} onChange={(event) => onChange(event.target.value)} className="min-h-24 border border-line bg-panel p-3 text-panel-fg" />
      </label>
      <p className="font-mono text-xs text-fg-muted">{clue.trim().split(/\s+/).filter(Boolean).length}/{CLUE_MAX_WORDS} words · {clue.length}/{CLUE_MAX_CHARS} characters · no digits</p>
      {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
      <Button type="submit" disabled={saving}>{saving ? "Writing clue…" : "Clue written"}</Button>
    </form>
  );
}

function GuessControls({ isGuesser, isPsychic, locking, error, onLock, hasCard }: {
  isGuesser: boolean; isPsychic: boolean; locking: boolean; error: string | null; onLock: () => void; hasCard: boolean;
}) {
  return (
    <div className="flex flex-1 flex-col gap-3 bg-surface-raised p-5 shadow-well">
      <div>
        <p className="font-mono text-[10px] uppercase tracking-[.12em] text-fg-muted">Your move</p>
        <p className="font-slab text-xl">{isGuesser ? "Place the needle" : "Watching"}</p>
        <p className="mt-1 text-sm text-fg-muted">
          {isGuesser ? "Drag along the arc, or use the arrow keys, to where you think the clue points, then lock it in." : isPsychic ? "Your target is hidden from everyone else until the guess locks." : "Watch the guesser set the needle."}
        </p>
      </div>
      {isGuesser && <Button disabled={locking || !hasCard} onClick={onLock}>{locking ? "Locking…" : "Confirm guess"}</Button>}
      {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
      <div className="mt-auto flex flex-col gap-1.5 border-t border-line pt-3">
        <p className="font-mono text-[10px] uppercase tracking-[.1em] text-fg-muted">Scoring</p>
        <p className="flex items-center gap-2 text-sm"><span aria-hidden className="h-3 w-3 bg-[#d94b45]" />Bullseye — 4</p>
        <p className="flex items-center gap-2 text-sm"><span aria-hidden className="h-3 w-3 bg-[#e49b55]" />Near — 3</p>
        <p className="flex items-center gap-2 text-sm"><span aria-hidden className="h-3 w-3 bg-[#e8cf75]" />Edge — 2</p>
      </div>
    </div>
  );
}

function RevealControls({ round }: { round: WavelengthRound | null }) {
  return (
    <div className="flex flex-1 flex-col justify-center gap-2 bg-surface-raised p-5 shadow-well">
      <p className="font-mono text-[10px] uppercase tracking-[.12em] text-fg-muted">Round locked</p>
      <p className="font-slab text-xl">{round?.status === "skipped" ? "Clue skipped" : `${round?.points ?? 0} points`}</p>
      <p className="text-sm text-fg-muted">The target is visible to everyone now. Next round starts automatically.</p>
    </div>
  );
}

/** The roster, live: each team's running score and what its players are
 * doing right now — writing, guessing, or just watching. */
function TablePanel({ players, board, rounds, statuses, current, viewerId }: {
  players: WavelengthPlayer[]; board: Board; rounds: WavelengthRound[]; statuses: ClueStatus[]; current: WavelengthRound | null; viewerId: string;
}) {
  const teams = board.mode === "coop" ? [0] : [0, 1];
  const statusFor = (player: WavelengthPlayer): { text: string; concealed: boolean } => {
    if (board.phase === "fill") {
      const pending = rounds.filter((round) => round.psychic_id === player.user_id && round.status === "pending");
      const done = pending.length > 0 && pending.every((round) => statuses.some((status) => status.round === round.round));
      return { text: done ? "Clues written" : player.absent ? "Absent" : "Writing…", concealed: false };
    }
    const isPsychic = current?.psychic_id === player.user_id;
    const isGuesser = current?.guesser_id === player.user_id;
    if (isPsychic) return { text: board.phase === "reveal" ? "Clue revealed" : "Clue locked", concealed: board.phase !== "reveal" };
    if (isGuesser) return { text: board.phase === "reveal" ? `Locked ${current?.points ?? 0}` : "Guessing now", concealed: false };
    return { text: player.absent ? "Absent" : "Watching", concealed: false };
  };
  return (
    <div className="flex min-h-0 flex-col gap-3">
      {teams.map((team) => (
        <div key={team} className="border border-line bg-surface-raised p-3">
          <div className="flex items-baseline justify-between">
            <p className="font-slab text-base">{board.mode === "coop" ? "Your team" : `Team ${team + 1}`}</p>
            <p className="font-slab font-mono text-xl tabular-nums">{board.teamScores[team] ?? 0}</p>
          </div>
          <div className="mt-2 flex flex-col gap-1.5">
            {players.filter((player) => player.team === team).map((player) => {
              const status = statusFor(player);
              return (
                <p key={player.user_id} className="flex justify-between text-sm">
                  <span>{player.user_id === viewerId ? "You" : player.display_name}</span>
                  <span className={status.concealed ? "text-hidden-text" : "text-fg-muted"}>{status.text}</span>
                </p>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

function ResultScreen({ result, scores, roundCount, rounds }: { result: WavelengthResult; scores: number[]; roundCount: number; rounds: WavelengthRound[] }) {
  if (result.mode === "coop") {
    const maximum = ({ short: 16, medium: 24, long: 32 } as const)[result.preset ?? "short"];
    return <section className="grid gap-4 rounded-sm bg-surface-raised p-5"><p className="font-slab text-2xl">{result.outcome === "win" ? "You won!" : "Not this time"}</p><p className="text-lg">{result.score} / {maximum} points</p><p>{result.bullseyes} {result.bullseyes === 1 ? "bullseye" : "bullseyes"}</p><p aria-label={`${result.stars ?? 0} star tier`} className="font-slab text-xl">{"★".repeat(result.stars ?? 0)}{"☆".repeat(3 - (result.stars ?? 0))}</p></section>;
  }
  const winner = result.outcome === "team_0_win" ? 0 : 1;
  const settledBy = rounds.length > roundCount ? "Sudden death" : scores[0] === scores[1] ? "Bullseye tiebreak" : null;
  return <section className="grid gap-4 rounded-sm bg-surface-raised p-5"><p className="font-slab text-2xl">Team {winner + 1} wins!</p><div className="flex gap-4 text-lg"><p>Team 1: {scores[0] ?? 0}</p><p>Team 2: {scores[1] ?? 0}</p></div>{settledBy && <p>{settledBy}</p>}</section>;
}
function Endpoints({ card }: { card: Card }) { return <div className="flex w-full justify-between gap-4 font-slab text-sm"><span>{card.left_label}</span><span className="text-right">{card.right_label}</span></div>; }

function Dial({ needle, setNeedle, target, interactive = false, label = "Guess needle" }: { needle?: number; setNeedle?: (position: number) => void; target?: number; interactive?: boolean; label?: string }) {
  const setFromPointer = (event: React.PointerEvent<SVGSVGElement>) => {
    if (!interactive || !setNeedle) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 1000;
    const y = -270 + ((event.clientY - rect.top) / rect.height) * 530;
    setNeedle(dialPosition(x, y));
  };
  const nudge = (event: React.KeyboardEvent<SVGSVGElement>) => {
    if (!interactive || !setNeedle || needle === undefined) return;
    const step = event.key === "ArrowLeft" ? -10 : event.key === "ArrowRight" ? 10 : 0;
    if (step) { event.preventDefault(); setNeedle(Math.max(0, Math.min(1000, needle + step))); }
  };
  // A pie slice from the pivot out to the arc, rather than a thin band near
  // the rim — the same shape for the neutral base (slice(0, 1000)) and for
  // each scoring wedge, so the dial reads as one filled half-circle.
  const slice = (from: number, to: number) => {
    const a = dialPoint(from), b = dialPoint(to);
    return `M ${DIAL.cx} ${DIAL.cy} L ${a.x} ${a.y} A ${DIAL.radius} ${DIAL.radius} 0 0 1 ${b.x} ${b.y} Z`;
  };
  const tip = needle === undefined ? null : dialPoint(needle, DIAL.radius - 30);
  return <svg role="slider" aria-label={label} aria-valuemin={0} aria-valuemax={1000} aria-valuenow={needle} tabIndex={interactive ? 0 : -1} onKeyDown={nudge} onPointerDown={setFromPointer} onPointerMove={(event) => { if (event.buttons) setFromPointer(event); }} viewBox="0 -270 1000 530" className={`w-full touch-none ${interactive ? "cursor-crosshair" : ""}`}>
    <path d={slice(0, 1000)} fill="#d7d1c3" />
    {target != null && scoringWedges(target).map((wedge, index) => <path key={index} d={slice(wedge.from, wedge.to)} fill={wedge.points === 4 ? "#d94b45" : wedge.points === 3 ? "#e49b55" : "#e8cf75"} />)}
    {tip && <line x1={DIAL.cx} y1={DIAL.cy} x2={tip.x} y2={tip.y} stroke="#24211c" strokeWidth="8" strokeLinecap="round" />}
    <circle cx={DIAL.cx} cy={DIAL.cy} r="14" fill="#24211c" />
  </svg>;
}

const CLUE_MESSAGES: Record<string, string> = { clue_required: "Write a clue before locking it in.", clue_contains_digit: "Clues cannot contain digits.", clue_too_many_words: "Keep your clue to 8 words or fewer.", clue_too_long: "Keep your clue to 100 characters or fewer." };
