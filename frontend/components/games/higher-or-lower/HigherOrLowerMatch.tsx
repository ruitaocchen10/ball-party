"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";

import { FinalStandings, type FinalStandingsRow } from "@/components/runtime/game-runtime/FinalStandings";
import { PauseBanner } from "@/components/runtime/game-runtime/PauseBanner";
import { PauseButton } from "@/components/runtime/game-runtime/PauseButton";
import { PostGameControls } from "@/components/runtime/game-runtime/PostGameControls";
import { PostGameNavigation } from "@/components/runtime/game-runtime/PostGameNavigation";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Reveal } from "@/components/foundation/ui-kit/Reveal";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Concealed } from "@/components/foundation/ui-kit/Concealed";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import {
  byPlacement,
  canCallNow,
  eraLabel,
  formatPoints,
  isSuddenDeath,
  liveStandings,
  questionPair,
  scoringModeLabel,
  suddenDeathRound,
  type Board,
  type Card as LadderCard,
  type Call,
  type CallStatus,
  type Player,
  type Standing,
} from "@/lib/games/higher-or-lower/board";
import { HEARTBEAT_MS, TICK_MS, VISIBLE_SLACK_MS, useMatchClock } from "@/lib/runtime/game-runtime/useMatchClock";
// TODO(architecture): pre-existing boundary violation — a game may depend on
// the contract, content, and the UI kit, never on platform/lobbies directly
// (docs/architecture/architecture.md). "Replay or return to lobby" is an
// orchestration decision; move it into game-runtime or an orchestration RPC
// the game can call instead of reaching into lobbies here.
// eslint-disable-next-line no-restricted-imports -- tracked by the TODO above, not fixed here.
import { postGameChoice } from "@/lib/platform/lobbies/actions";
import { teamLogoCode } from "@/lib/foundation/content/nfl/team-logos";
import { createClient } from "@/lib/supabase/client";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";

/**
 * The ladder, on one screen.
 *
 * The server deals the ladder, owns its phase and deadline, and publishes only
 * revealed points. This client renders that projection, repeatedly asks the
 * server to expire a passed deadline, and reconciles after reconnects.
 *
 * The withheld number is withheld by the server. The challenger's row simply
 * does not carry its points until its question reveals, so the concealed panel
 * below is an honest rendering of an absent value rather than a UI that knows
 * something it is choosing not to say. See migration 0032.
 */
export function HigherOrLowerMatch({
  matchId,
  viewerId,
  roomCode,
  isHost,
  paused = false,
  initial,
}: {
  matchId: string;
  viewerId: string;
  roomCode: string | null;
  isHost: boolean;
  paused?: boolean;
  initial: {
    board: Board;
    cards: LadderCard[];
    players: Player[];
    calls: Call[];
    statuses: CallStatus[];
    standings: Standing[];
  };
}) {
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);
  const [board, setBoard] = useState<Board>(initial.board);
  const [cards, setCards] = useState<LadderCard[]>(initial.cards);
  const [players, setPlayers] = useState<Player[]>(initial.players);
  const [calls, setCalls] = useState<Call[]>(initial.calls);
  const [statuses, setStatuses] = useState<CallStatus[]>(initial.statuses);
  const [standings, setStandings] = useState<Standing[]>(initial.standings);
  const [pendingCall, setPendingCall] = useState(false);
  const [callError, setCallError] = useState<string | null>(null);
  const [isPaused, setIsPaused] = useState(paused);
  const [pendingAdvance, setPendingAdvance] = useState(false);
  const [advanceError, setAdvanceError] = useState<string | null>(null);

  // A solo run has no lobby to have come from — the same signal FinalScreen
  // already reads below to tell a solo ending from a room's. Solo trades the
  // shared clock for the player's own pace: no call countdown, and a tap on
  // `advance` instead of a timed pause to leave a reveal.
  const isSolo = roomCode === null;

  const applyBoard = useCallback((row: Partial<Board>) => {
    if (
      row.questionCount == null || row.currentQuestion == null || row.scoringMode == null ||
      row.seasonFrom == null || row.seasonTo == null || row.phase == null ||
      row.phaseDeadline === undefined || row.serverNow == null
    ) return;
    setBoard({
      questionCount: row.questionCount,
      currentQuestion: row.currentQuestion,
      scoringMode: row.scoringMode,
      seasonFrom: row.seasonFrom,
      seasonTo: row.seasonTo,
      phase: row.phase,
      phaseDeadline: row.phaseDeadline,
      serverNow: row.serverNow,
    });
  }, []);

  const refetch = useCallback(async () => {
    const supabase = getClient();
    const [state, cardRows, playerRows, callRows, statusRows, standingRows] = await Promise.all([
      supabase.schema("higher_or_lower").rpc("state", { p_match_id: matchId }),
      supabase.from("higher_or_lower_cards").select("*").eq("match_id", matchId).order("ordinal"),
      // Named explicitly: the compound (match_id, user_id) FKs on the calls
      // and call_statuses tables give PostgREST a second, many-to-many path to
      // profiles alongside this table's direct one, so an unqualified
      // `profiles(...)` embed 300s as ambiguous (PGRST201). See the matching
      // note on the server fetch in app/match/[id]/page.tsx.
      supabase.from("higher_or_lower_players").select("*, profiles!higher_or_lower_players_user_id_fkey(display_name, avatar_url)").eq("match_id", matchId).order("seat"),
      supabase.from("higher_or_lower_calls").select("*").eq("match_id", matchId).order("created_at"),
      supabase.from("higher_or_lower_call_statuses").select("*").eq("match_id", matchId),
      supabase.from("match_players").select("*").eq("match_id", matchId),
    ]);
    if (state.data) applyBoard(boardFromState(state.data as HigherOrLowerState));
    if (cardRows.data) setCards(cardRows.data as LadderCard[]);
    if (playerRows.data) {
      setPlayers(playerRows.data.map(({ profiles, ...seat }) => ({
        ...seat,
        display_name: profiles?.display_name ?? "Unknown player",
        avatar_url: profiles?.avatar_url ?? null,
      })) as Player[]);
    }
    if (callRows.data) setCalls(callRows.data as Call[]);
    if (statusRows.data) setStatuses(statusRows.data as CallStatus[]);
    if (standingRows.data) setStandings(standingRows.data);
  }, [applyBoard, getClient, matchId]);

  const { remainingMs, reconcile } = useMatchClock({
    serverNow: board.serverNow,
    deadline: board.phase === "complete" ? null : board.phaseDeadline,
    visibleSlackMs: VISIBLE_SLACK_MS,
    // The tick below is also how this player says they are still here. Asking
    // only at a passed deadline would put nobody on the record inside a
    // question, and the server latches a player who ticked nowhere in one
    // absent at its reveal.
    heartbeatMs: HEARTBEAT_MS,
    paused: isPaused,
    expire: () => getClient().schema("higher_or_lower").rpc("tick", { p_match_id: matchId }).then(({ data }) => {
      if (data) applyBoard(boardFromState(data as HigherOrLowerState));
    }),
    reconcile: refetch,
  });

  useEffect(() => {
    let cleanup: (() => void) | null = null;
    let cancelled = false;
    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;
      const channel = supabase
        .channel(`higher-or-lower:${matchId}`)
        .on("postgres_changes", { event: "*", schema: "public", table: "higher_or_lower_matches", filter: `match_id=eq.${matchId}` }, (payload) => {
          const row = payload.new as HigherOrLowerMatchRow;
          // A row payload has no server timestamp. Keep the last one supplied
          // by state() rather than quietly substituting this browser's clock;
          // the next reconciliation supplies a fresh authoritative offset.
          setBoard((previous) => ({ ...previous, ...boardFromRow(row) }));
        })
        .on("postgres_changes", { event: "*", schema: "public", table: "higher_or_lower_cards", filter: `match_id=eq.${matchId}` }, (payload) => {
          const card = payload.new as LadderCard;
          // Endless solo (0046) appends a brand-new ordinal past the pre-dealt
          // ladder rather than updating one already on the client — that
          // arrives as an INSERT with no existing row to replace, so it must
          // be appended or the extended card never reaches this screen.
          setCards((previous) => previous.some((candidate) => candidate.ordinal === card.ordinal)
            ? previous.map((candidate) => candidate.ordinal === card.ordinal ? card : candidate)
            : [...previous, card].sort((a, b) => a.ordinal - b.ordinal));
          // A reveal changes which existing call rows RLS permits. Calls do not
          // emit a new event at that moment, so re-read their policy projection.
          if (card.revealed_at) void refetch();
        })
        .on("postgres_changes", { event: "*", schema: "public", table: "higher_or_lower_players", filter: `match_id=eq.${matchId}` }, (payload) => {
          const player = payload.new as Player;
          setPlayers((previous) => previous.map((candidate) => candidate.user_id === player.user_id ? {
            ...candidate, ...player,
          } : candidate));
        })
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "higher_or_lower_calls", filter: `match_id=eq.${matchId}` }, (payload) => {
          const call = payload.new as Call;
          setCalls((previous) => previous.some((candidate) => candidate.user_id === call.user_id && candidate.question === call.question)
            ? previous : [...previous, call]);
        })
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "higher_or_lower_call_statuses", filter: `match_id=eq.${matchId}` }, (payload) => {
          const status = payload.new as CallStatus;
          setStatuses((previous) => previous.some((candidate) => candidate.user_id === status.user_id && candidate.question === status.question)
            ? previous : [...previous, status]);
        })
        // Written once, at completion (0009's finish_match, called from #28's
        // ending), so there is never an existing row to merge into — an upsert
        // into the standings the final screen reads.
        .on("postgres_changes", { event: "*", schema: "public", table: "match_players", filter: `match_id=eq.${matchId}` }, (payload) => {
          const row = payload.new as Standing;
          setStandings((previous) => [...previous.filter((s) => s.user_id !== row.user_id), row]);
        })
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${matchId}` }, (payload) => {
          setIsPaused((payload.new as { status?: string }).status === "paused");
        })
        .subscribe((status) => { if (status === "SUBSCRIBED") reconcile(); });
      cleanup = () => { void supabase.removeChannel(channel); };
    })();
    return () => { cancelled = true; cleanup?.(); };
  }, [matchId, reconcile, refetch]);

  const { anchor, challenger: dealtChallenger } = questionPair(cards, board.currentQuestion);
  // The card and board changes commit together, but Realtime delivers table
  // payloads independently. The board phase is the authoritative permission to
  // display this question's answer, so a card event that wins that small race
  // cannot show its points while this screen still renders a call.
  const challenger = dealtChallenger && (
    board.phase === "reveal" || board.phase === "sudden_death_reveal" || board.phase === "complete"
  )
    ? dealtChallenger
    : dealtChallenger ? { ...dealtChallenger, points: null, revealed_at: null } : null;
  const myCall = calls.find((call) => call.question === board.currentQuestion && call.user_id === viewerId);
  const viewerPlayer = players.find((player) => player.user_id === viewerId);
  const lockedIn = new Set(statuses.filter((status) => status.question === board.currentQuestion).map((status) => status.user_id));
  const makeCall = async (direction: "higher" | "lower") => {
    setPendingCall(true);
    setCallError(null);
    const { data, error } = await getClient().schema("higher_or_lower").rpc("call", {
      p_match_id: matchId,
      p_direction: direction,
    });
    setPendingCall(false);
    if (error) {
      setCallError(CALL_MESSAGES[error.message] ?? error.message);
      return;
    }
    if (data) {
      const call = data as Call;
      setCalls((previous) => previous.some((candidate) => candidate.user_id === call.user_id && candidate.question === call.question)
        ? previous : [...previous, call]);
      setStatuses((previous) => previous.some((status) => status.user_id === call.user_id && status.question === call.question)
        ? previous : [...previous, { match_id: call.match_id, question: call.question, user_id: call.user_id }]);
      // A player who locks in after someone else needs the rows that became
      // visible with their call. Future calls still arrive as individual
      // Realtime inserts rather than a client-side reveal batch.
      await refetch();
    }
  };

  // Solo's replacement for the timer that pushes a group board out of its
  // reveal. The board row this writes arrives back over the Realtime
  // subscription already wired up above, so there is nothing to apply here
  // beyond surfacing an error.
  const advance = async () => {
    setPendingAdvance(true);
    setAdvanceError(null);
    const { error } = await getClient().schema("higher_or_lower").rpc("advance", { p_match_id: matchId });
    setPendingAdvance(false);
    if (error) setAdvanceError(error.message);
  };

  if (board.phase === "complete") {
    return (
      <main className={isSolo
        ? "app-page flex-1"
        : "mx-auto flex w-full max-w-2xl flex-1 flex-col gap-5 px-6 py-10"}>
        <FinalScreen
          standings={standings}
          players={players}
          viewerId={viewerId}
          roomCode={roomCode}
          matchId={matchId}
          isHost={isHost}
        />
      </main>
    );
  }

  return (
    <main className={isSolo
      ? "app-page flex-1"
      : "mx-auto flex w-full min-h-0 flex-1 flex-col gap-4 overflow-hidden px-4 pt-3 pb-4"}>
      <header className={isSolo
        ? "mx-auto flex w-full max-w-5xl flex-col gap-3 border-b border-line pb-5 sm:flex-row sm:items-end sm:justify-between"
        : "flex shrink-0 items-baseline justify-between gap-3"}>
        <div>
          {isSolo ? <p className="font-mono text-[10px] font-bold tracking-[0.16em] text-hidden-text uppercase">Solo challenge</p> : null}
          <h1 className={isSolo ? "mt-1 font-slab text-4xl leading-none uppercase sm:text-5xl" : "font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase"}>
            {isSolo ? "Higher or lower" : questionLabel(board, "visual", isSolo)}
          </h1>
          {isSolo ? (
            <p className="mt-2 font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase">
              <span>{questionLabel(board, "visual", isSolo)}</span>
              <span aria-hidden> · make the streak last</span>
            </p>
          ) : null}
        </div>
        <div className="flex items-center gap-3">
          <p
            role="note"
            aria-label="Board format"
            className="font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase"
          >
            {scoringModeLabel(board)} · {eraLabel(board)}
          </p>
          {isHost ? <PauseButton matchId={matchId} paused={isPaused} /> : null}
        </div>
      </header>

      {isPaused ? <PauseBanner /> : null}

      {/* The party games share a desktop table shape: time and action at left,
          the active play in the roomy centre, and everyone else at right.
          This game's rails deliberately stay slimmer than Auction's: a call
          and a streak need less room than bidding controls or full rosters.
          Source order still makes the phone read the cards before the choice. */}
      <div className={isSolo
        ? "mx-auto mt-5 flex w-full max-w-5xl flex-col gap-5"
        : "grid min-h-0 flex-1 grid-rows-[minmax(0,1fr)_auto_minmax(4rem,1fr)] gap-3 lg:grid-cols-[12rem_minmax(0,1fr)_14rem] lg:grid-rows-1"}>
        <section className={isSolo ? "flex flex-col gap-3" : "flex min-h-0 flex-col gap-3 lg:col-start-2 lg:row-start-1"} aria-label="The comparison">
          {anchor && challenger ? (
            <div className={isSolo ? "grid gap-4 md:grid-cols-2" : "grid min-h-0 flex-1 gap-3 sm:grid-cols-2"}>
              <LadderCardPanel
                label="Anchor"
                card={anchor}
                caption="What the challenger is priced against."
              />
              <LadderCardPanel
                label="Challenger"
                card={challenger}
                caption="Higher or lower than the anchor?"
                action={
                  <CallActions
                    canCall={canCallNow(board, viewerPlayer)}
                    call={myCall ?? null}
                    pending={pendingCall}
                    paused={isPaused}
                    onCall={makeCall}
                  />
                }
              />
            </div>
          ) : (
            <p className="text-sm text-fg-muted">Waiting for the next card…</p>
          )}
        </section>

        <section className={isSolo
          ? "mx-auto flex w-full max-w-2xl flex-col gap-3"
          : "flex shrink-0 flex-col gap-3 lg:col-start-1 lg:row-start-1"} aria-label="Your call">
          {isSolo ? (
            board.phase === "reveal" ? (
              <SoloContinue pending={pendingAdvance} error={advanceError} onContinue={advance} />
            ) : null
          ) : (
            <MatchClock className="lg:order-first" phase={board.phase} remainingMs={remainingMs} />
          )}
          <CallFeedback call={myCall ?? null} error={callError} />
        </section>

      {/* Both points panels are hidden from assistive technology, so this
          region is the complete announcement of what is on screen. */}
      <p role="status" className="sr-only">
        {anchor && challenger
          ? `${questionLabel(board, "spoken", isSolo)}. ${anchor.display_name} scored ${formatPoints(anchor.points)} fantasy points. ${challenger.points === null ? `${challenger.display_name} is hidden.` : `${challenger.display_name} scored ${formatPoints(challenger.points)} fantasy points.`}`
          : ""}
      </p>

        {isSolo ? <SoloRunSummary player={viewerPlayer ?? null} /> : null}

        {!isSolo ? <aside aria-label="The table" className="min-h-0 overflow-y-auto lg:col-start-3 lg:row-start-1">
          <div className="flex flex-col border border-line bg-surface-raised">
            <header className="flex items-baseline justify-between gap-2 px-3 py-2">
              <h2 className="font-mono text-[10px] font-bold tracking-[0.15em] text-fg-muted uppercase">Standings</h2>
              <span className="font-mono text-[9px] tracking-[0.08em] text-fg-muted uppercase">Correct · best</span>
            </header>
            <ul className="border-t border-line divide-y divide-line">
              {liveStandings(players, board.phase).map(({ player, rank, tied }) => {
                const call = calls.find((candidate) => candidate.question === board.currentQuestion && candidate.user_id === player.user_id);
                return (
                  <li
                    key={player.user_id}
                    className={`grid grid-cols-[1.55rem_1.85rem_minmax(0,1fr)_auto] items-center gap-2 px-3 py-2.5 transition-col ${rank === 1 ? "bg-panel/5" : "hover:bg-panel/5"}`}
                  >
                    <span className={`font-mono text-xs font-bold tabular-nums ${rank === 1 ? "text-hidden-text" : "text-fg-muted"}`}>{tied ? "T-" : "#"}{rank}</span>
                    <StandingsAvatar name={player.display_name} avatarUrl={player.avatar_url} mine={player.user_id === viewerId} />
                <span className="flex min-w-0 flex-col gap-0.5">
                  <span className="flex min-w-0 items-center gap-1 font-slab text-base leading-none uppercase">
                    <span className="truncate">{player.display_name}</span>
                    {player.user_id === viewerId ? <span className="font-mono text-[8px] tracking-[0.08em] text-hidden-text">YOU</span> : null}
                  </span>
                  <span className="truncate font-mono text-[9px] tracking-[0.07em] text-fg-muted uppercase">
                    {standingStatus(player, call ?? null, lockedIn.has(player.user_id), board.phase)}
                  </span>
                </span>
                    <span className="flex flex-col items-end whitespace-nowrap font-mono text-[9px] leading-tight tabular-nums uppercase">
                      <strong className="text-xs text-fg">{player.correct_count} correct</strong>
                      <span className="text-fg-muted">{player.best_streak} best</span>
                    </span>
                    <span className="sr-only">{player.current_streak} now · {player.best_streak} best · {player.correct_count} correct</span>
                  </li>
                );
              })}
            </ul>
          </div>
        </aside> : null}
      </div>
    </main>
  );
}

/** A solo player needs progress, not a one-row leaderboard. */
function SoloRunSummary({ player }: { player: Player | null }) {
  return (
    <section aria-label="Your run" className="grid grid-cols-3 divide-x divide-line border border-line bg-surface-raised">
      <RunStat label="Current" value={player?.current_streak ?? 0} />
      <RunStat label="Best" value={player?.best_streak ?? 0} />
      <RunStat label="Correct" value={player?.correct_count ?? 0} />
    </section>
  );
}

function RunStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="px-3 py-3 text-center">
      <p className="font-mono text-[9px] font-bold tracking-[0.14em] text-fg-muted uppercase">{label}</p>
      <p className="mt-1 font-slab text-3xl leading-none tabular-nums">{value}</p>
    </div>
  );
}

/**
 * Names a winner, so the ladder ends rather than merely stopping. Standings
 * are #28's ending — total correct, then best streak, with an exact tie
 * resolved in sudden death —
 * already ranked the way the auction's are, so this reads exactly the same
 * platform record the auction's own final screen does.
 */
function FinalScreen({
  standings,
  players,
  viewerId,
  roomCode,
  matchId,
  isHost,
}: {
  standings: Standing[];
  players: Player[];
  viewerId: string;
  roomCode: string | null;
  matchId: string;
  isHost: boolean;
}) {
  const ranked = byPlacement(standings);
  const nameOf = (userId: string) => players.find((p) => p.user_id === userId)?.display_name ?? "Unknown player";
  const avatarOf = (userId: string) => players.find((p) => p.user_id === userId)?.avatar_url ?? null;
  const winners = ranked.filter((s) => s.placement === 1);
  const headline =
    winners.length === 0
      ? "Game over"
      : winners.length === 1
        ? `${nameOf(winners[0].user_id)} wins`
        : `${winners.map((w) => nameOf(w.user_id)).join(" & ")} tie`;

  // No per-user roster here — the ladder has nothing to draft — so every
  // row renders with no `roster` and, per FinalStandings, no disclosure
  // chevron at all rather than an empty one.
  const rows: FinalStandingsRow[] = ranked.map((standing) => {
    const player = players.find((p) => p.user_id === standing.user_id);
    return {
      userId: standing.user_id,
      rank: standing.placement ?? ranked.length,
      name: nameOf(standing.user_id),
      avatarUrl: avatarOf(standing.user_id),
      isViewer: standing.user_id === viewerId,
      statLine: player ? `${player.correct_count} correct · ${player.best_streak} best` : "",
    };
  });

  return (
    <>
      <FinalStandings headline={headline} rows={rows} />

      {roomCode ? <PostGameNavigation matchId={matchId} roomCode={roomCode} /> : null}
      {roomCode ? (
        <PostGameControls matchId={matchId} roomCode={roomCode} isHost={isHost} />
      ) : null}

      {!roomCode ? (
        <div className="mt-2 flex flex-col gap-2">
          <form action={postGameChoice}>
            <input type="hidden" name="match_id" value={matchId} />
            <input type="hidden" name="choice" value="replay" />
            <Button type="submit" fullWidth>Play again</Button>
          </form>
          <Link
            href="/"
            className="text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
          >
            Back home
          </Link>
        </div>
      ) : null}
    </>
  );
}

const CALL_MESSAGES: Record<string, string> = {
  already_called: "You already locked in this question.",
  call_not_open: "Calls are not open right now.",
  call_deadline_passed: "The call window has closed.",
  match_not_playing: "This match isn't accepting moves right now.",
};

/**
 * The two buttons, and what became of the call they make.
 *
 * A row with no direction is the miss the server wrote when the deadline
 * passed. It is scored exactly as a wrong call — that is the point of writing
 * it — so this line is the only place the difference is visible, and it says
 * "ran out of time" rather than reporting a call nobody made.
 */
function CallActions({
  canCall, call, pending, paused, onCall,
}: {
  canCall: boolean;
  call: Call | null;
  pending: boolean;
  paused: boolean;
  onCall: (direction: "higher" | "lower") => void;
}) {
  const disabled = !canCall || call !== null || pending || paused;
  return (
    <section aria-label="Make your call" className="grid gap-2 sm:grid-cols-2">
      <Button disabled={disabled} onClick={() => onCall("higher")}>Higher</Button>
      <Button disabled={disabled} variant="ghost" onClick={() => onCall("lower")}>Lower</Button>
    </section>
  );
}

function CallFeedback({ call, error }: { call: Call | null; error: string | null }) {
  return (
    <section aria-label="Your call status" className="grid shrink-0 gap-2">
      <AnimatedMessage className="sm:col-span-2 font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase">
        {call ? (call.timed_out ? "You ran out of time." : `You called ${call.direction}.`) : null}
      </AnimatedMessage>
      <AnimatedMessage role="alert" className="sm:col-span-2 text-sm text-red-700">
        {error}
      </AnimatedMessage>
    </section>
  );
}

type HigherOrLowerState = {
  question_count: number | null;
  current_question: number | null;
  scoring_mode: string | null;
  season_from: number | null;
  season_to: number | null;
  phase: Board["phase"] | null;
  phase_deadline: string | null;
  server_now: string | null;
};

type HigherOrLowerMatchRow = {
  question_count: number;
  current_question: number;
  scoring_mode: string;
  season_from: number;
  season_to: number;
  phase: Board["phase"];
  phase_deadline: string | null;
};

function boardFromState(row: HigherOrLowerState): Partial<Board> {
  return {
    questionCount: row.question_count ?? undefined,
    currentQuestion: row.current_question ?? undefined,
    scoringMode: row.scoring_mode ?? undefined,
    seasonFrom: row.season_from ?? undefined,
    seasonTo: row.season_to ?? undefined,
    phase: row.phase ?? undefined,
    phaseDeadline: row.phase_deadline,
    serverNow: row.server_now ?? undefined,
  };
}

function boardFromRow(row: HigherOrLowerMatchRow): Omit<Board, "serverNow"> {
  return {
    questionCount: row.question_count,
    currentQuestion: row.current_question,
    scoringMode: row.scoring_mode,
    seasonFrom: row.season_from,
    seasonTo: row.season_to,
    phase: row.phase,
    phaseDeadline: row.phase_deadline,
  };
}

/** The visible heading and screen-reader announcement must name a live board
 * identically; only sudden death's punctuation differs for natural speech.
 *
 * Solo never reaches sudden death — there is nobody to tie with — and never
 * carries a fixed "of N" ceiling: the ladder (0046) keeps extending past its
 * pre-dealt twelve for as long as the player keeps calling correctly. */
function questionLabel(board: Board, audience: "visual" | "spoken", isSolo: boolean): string {
  if (isSuddenDeath(board.phase)) {
    return audience === "visual"
      ? `Sudden death · Round ${suddenDeathRound(board)}`
      : `Sudden death, round ${suddenDeathRound(board)}`;
  }
  return isSolo || board.currentQuestion > board.questionCount
    ? `Question ${board.currentQuestion}`
    : `Question ${board.currentQuestion} of ${board.questionCount}`;
}

/** Solo's untimed stand-in for the clock: the reveal waits here for a tap
 * rather than a deadline, the same way `MatchClock` occupies this rail for a
 * group board. */
function SoloContinue({
  pending,
  error,
  onContinue,
}: {
  pending: boolean;
  error: string | null;
  onContinue: () => void;
}) {
  return (
    <section aria-label="Continue" className="flex flex-col gap-2 rounded bg-surface-raised p-3 shadow-well">
      <p className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">The answer is revealed</p>
      <Button disabled={pending} onClick={onContinue}>Continue</Button>
      <AnimatedMessage role="alert" className="text-sm text-red-700">{error}</AnimatedMessage>
    </section>
  );
}

function MatchClock({
  phase,
  remainingMs,
  className = "",
}: {
  phase: Board["phase"];
  remainingMs: number | null;
  className?: string;
}) {
  const seconds = remainingMs === null ? null : Math.ceil(remainingMs / 1_000);
  const duration = phase === "board_intro" ? 5_000 : phase === "call" ? 12_000 : phase === "sudden_death_call" ? 8_000 : 4_000;
  const fraction = remainingMs === null ? 0 : Math.min(1, remainingMs / (duration - VISIBLE_SLACK_MS));
  const label = phase === "board_intro"
    ? "The board is coming into view"
    : phase === "call" || phase === "sudden_death_call"
      ? "Make your call"
      : phase === "reveal" || phase === "sudden_death_reveal"
        ? "The answer is revealed"
        : "Match complete";
  return (
    <section aria-label="Clock" className={`rounded bg-surface-raised p-3 shadow-well ${className}`}>
      <p className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">{label}</p>
      <p className="mt-1 font-slab text-3xl leading-none tabular-nums" aria-hidden>{seconds === null ? "—" : `${seconds}s`}</p>
      <div role="timer" aria-label={seconds === null ? "No timer" : `${seconds} seconds left`} className="mt-3 h-1.5 overflow-hidden rounded-full bg-line">
        <div className="h-full bg-panel transition-[width]" style={{ width: `${fraction * 100}%`, transitionDuration: `${TICK_MS}ms` }} />
      </div>
    </section>
  );
}

function StandingsAvatar({ name, avatarUrl, mine }: { name: string; avatarUrl: string | null; mine: boolean }) {
  const [failed, setFailed] = useState(false);
  if (avatarUrl && !failed) {
    return <img src={avatarUrl} alt="" onError={() => setFailed(true)} className="h-7 w-7 shrink-0 rounded-full object-cover" />;
  }
  return (
    <span aria-hidden className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full font-slab text-base ${mine ? "bg-hidden text-panel" : "bg-surface text-fg"}`}>
      <span className="font-slab-optical-center">{name.slice(0, 1).toUpperCase()}</span>
    </span>
  );
}

function standingStatus(player: Player, call: Call | null, locked: boolean, phase: Board["phase"]): string {
  if (player.eliminated_at !== null) return "ELIMINATED";
  if (isSuddenDeath(phase) && !player.sudden_death) return "WATCHING";
  if (player.absent) return "AWAY";
  if (call?.timed_out) return "TIMED OUT";
  if (locked) return call?.direction ?? "LOCKED";
  return "THINKING";
}

/**
 * One card and its number. The same component for both sides of a question,
 * because they are the same card at two moments — every challenger becomes the
 * next anchor — and rendering them from two components is how the two drift.
 */
function LadderCardPanel({
  label,
  card,
  caption,
  action,
}: {
  label: string;
  card: LadderCard;
  caption: string;
  action?: ReactNode;
}) {
  const logoCode = teamLogoCode(card.team);
  return (
    <section role="group" aria-label={label} className="flex min-h-0 flex-col gap-2">
      {/* Keep the player identity and the score as one card. This matches the
          auction lot's portrait-forward hierarchy while the score remains the
          distinct reveal beat Higher or Lower depends on. */}
      <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden border border-line bg-surface-raised text-center shadow-well">
        <span className="absolute top-3 left-3 font-slab text-xl leading-none text-fg uppercase">{card.position}</span>
        {logoCode ? <TeamLogo code={logoCode} className="absolute top-3 right-3 h-8 w-8" /> : <span className="absolute top-3 right-3 font-mono text-[11px] font-bold tracking-[0.12em] text-fg-muted uppercase">{card.team}</span>}
        <div className="flex min-h-0 flex-1 flex-col items-center justify-center px-4 py-5">
          <LadderPortrait name={card.display_name} headshotUrl={card.headshot_url} />
          <h2 className="mt-3 max-w-full truncate font-slab text-3xl leading-none text-fg uppercase">{card.display_name}</h2>
          <LadderMatchup card={card} />
        </div>

        {/* Both cards reserve this row. The challenger fills it with the call,
            while the anchor keeps it quiet so their player details and score
            reveals stay horizontally aligned. */}
        <div className={`min-h-[4.5rem] px-3.5 py-3 text-left${action ? " border-t border-line" : ""}`}>
          {action}
        </div>

        {/* Both faces are out of the accessibility tree: a weave with three
            question marks and a big number are visual idioms, and the screen's
            status region says the whole thing in one ordered sentence instead. */}
        <div className="border-t border-line">
          <Reveal
            revealed={card.points !== null}
            concealed={
              <Concealed label="Fantasy points, hidden until this question reveals" className="rounded-none px-3.5 py-4">
                <div aria-hidden className="relative flex flex-col items-center gap-1 text-center">
                  <span className="font-mono text-xs font-bold tracking-[0.15em] text-panel uppercase">
                    Fantasy points
                  </span>
                  <span className="font-slab text-4xl leading-none text-panel">? ? ?</span>
                </div>
              </Concealed>
            }
          >
            <div aria-hidden className="flex flex-col items-center gap-1 bg-panel px-3.5 py-4 text-center text-panel-fg">
              <span className="font-mono text-xs font-bold tracking-[0.15em] text-panel-muted uppercase">
                Fantasy points
              </span>
              <span className="min-w-0 font-slab text-4xl leading-none tabular-nums">
                {formatPoints(card.points)}
              </span>
            </div>
          </Reveal>
        </div>
      </div>

      <p className="font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase">{caption}</p>
    </section>
  );
}

function LadderTeam({ code }: { code: string }) {
  const logoCode = teamLogoCode(code);
  return (
    <span className="flex min-w-0 flex-1 flex-col items-center gap-1.5">
      {logoCode ? <TeamLogo code={logoCode} className="h-9 w-9" /> : <span aria-hidden className="h-9 w-9 rounded-full border border-line" />}
      <span className="font-slab text-lg leading-none text-fg uppercase">{code}</span>
    </span>
  );
}

function LadderMatchup({ card }: { card: LadderCard }) {
  const weekly = card.week !== null && card.opponent !== null;
  return (
    <div className="mt-4 w-full border-t border-line pt-3" aria-label={weekly ? `${card.season}, week ${card.week}, ${card.team} versus ${card.opponent}` : `${card.season} season, ${card.team}`}>
      <p className="font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">{weekly ? `${card.season} · week ${card.week}` : `${card.season} season`}</p>
      {weekly ? (
        <div className="mt-2 flex items-center gap-3">
          <LadderTeam code={card.team} />
          <span className="font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">vs</span>
          <LadderTeam code={card.opponent!} />
        </div>
      ) : <div className="mt-2 flex justify-center"><LadderTeam code={card.team} /></div>}
    </div>
  );
}

/** The same resilient, circular identity treatment used by auction lots. */
function LadderPortrait({ name, headshotUrl }: { name: string; headshotUrl: string | null }) {
  const [failed, setFailed] = useState(false);
  if (headshotUrl && !failed) {
    return (
      <img
        src={headshotUrl}
        alt=""
        onError={() => setFailed(true)}
        className="h-28 w-28 shrink-0 rounded-full bg-panel-shade object-cover object-top"
      />
    );
  }
  return (
    <span aria-hidden className="flex h-28 w-28 shrink-0 items-center justify-center rounded-full bg-hidden font-slab text-4xl text-panel">
      <span className="font-slab-optical-center">{name.slice(0, 1).toUpperCase()}</span>
    </span>
  );
}
