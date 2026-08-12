"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";

import { TopBar } from "@/components/layout/TopBar";
import { Button } from "@/components/ui/Button";
import { Card, CardMeta, CardTitle } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import {
  BLOCKED_TEXT,
  INCREMENTS,
  blockedReason,
  byPlacement,
  canAfford,
  filledSlots,
  hasPassed,
  highBidder,
  lotIdentityLine,
  lotAt,
  matchupLine,
  revealedTotal,
  rosterSlots,
  standingPrice,
  slotFor,
  viewerPhase,
  type Bid,
  type AuctionFormat,
  type Lot,
  type Player,
  type Seat,
  type Standing,
  type Slot,
  type Turn,
} from "@/lib/auction/board";
import { createClient, createRealtimeClient } from "@/lib/supabase/client";

/**
 * The whole game, on one screen.
 *
 * Two decisions shape everything below.
 *
 * Moves go straight from the browser to Postgres with rpc(). They are not
 * server actions: every other mutation in this app is a navigation that ends in
 * a redirect, and a full page round trip per bid inside a ten-second turn is
 * not a game. It is safe for the same reason the server action was — the RPC
 * derives identity from auth.uid() and validates the move itself. That was
 * never something the server action was providing.
 *
 * And nothing here is optimistic. A bid is not on screen until the server
 * confirms it. Optimism buys very little when the round trip is one hop to
 * Postgres, and it costs the one thing this game cannot afford: a price on
 * screen that the server then rejects, in a game where the number on screen is
 * what everybody is reasoning about.
 */

/** The server's real deadline is longer than the visible clock, which stops
 *  short so a bid sent as the bar empties still has real deadline behind it.
 *  These mirror the intervals in the migrations; the server remains the only
 *  thing that decides when a phase is actually over. */
const VISIBLE_SLACK_MS = 500;
const TICK_MS = 100;
const DURATION_MS: Record<Turn["phase"], number> = {
  lot_preview: 5_000,
  bidding: 20_000,
  sold: 5_000,
};

/**
 * Expiry is asked for repeatedly, not once.
 *
 * The previous version fired exactly one request per state and latched. If that
 * one attempt no-opped -- and for the timer-only phases it fired at exactly the
 * deadline with no slack, so any client whose clock ran a millisecond fast got
 * a no-op -- then nobody ever asked again and the auction sat there until the
 * janitor swept it a minute later. Three lots in one playtest took 81s, 127s
 * and 271s that way, one of them with no player actions at all.
 *
 * Asking again is free: the server re-checks in its own time under the match
 * lock and does nothing if it disagrees.
 */
const RETRY_MS = 1_000;

/** How far past a deadline the screen has to look before it stops believing
 *  itself and refetches. Well behind RETRY_MS, so this only runs when expiry
 *  has already failed to move things along. */
const STALE_MS = 4_000;

/**
 * The auction RPCs raise short machine-readable strings — see
 * supabase/migrations/20260809222000_0011_auction_bidding.sql. Anything absent
 * here is a bug rather than a player-facing condition, so it surfaces raw
 * instead of being flattened into a friendly lie.
 */
const MESSAGES: Record<string, string> = {
  not_your_turn: "It isn't your turn.",
  already_passed: "You already passed on this lot.",
  not_eligible: "You have no open slot for this lot.",
  insufficient_budget: "That's more than you have left.",
  bid_not_whole: "Bids are in whole dollars.",
  bid_not_increasing: "Your bid must be higher than the current price.",
  bidding_not_open: "Bidding has not opened yet.",
  match_not_playing: "This game has ended.",
  not_a_participant: "You're not in this game.",
  not_authenticated: "Sign in first.",
};

type Initial = {
  turn: Turn;
  serverNow: string;
  lots: Lot[];
  players: Player[];
  bids: Bid[];
  standings: Standing[];
  format: AuctionFormat | null;
};

export function AuctionMatch({
  matchId,
  viewerId,
  displayName,
  roomCode,
  initial,
}: {
  matchId: string;
  viewerId: string;
  displayName: string | null;
  roomCode: string | null;
  initial: Initial;
}) {
  // Built on first use rather than during render. createClient() reaches for
  // document.cookie, which does not exist while this component renders on the
  // server, and @supabase/ssr throws there rather than degrading. Every caller
  // below runs in an effect or an event handler, so all of them are in a
  // browser by the time they ask. In a browser the underlying client is a
  // singleton, so this hands back the same instance the subscription uses.
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);

  const [turn, setTurn] = useState<Turn>(initial.turn);
  const [lots, setLots] = useState<Lot[]>(initial.lots);
  const [players, setPlayers] = useState<Player[]>(initial.players);
  const [bids, setBids] = useState<Bid[]>(initial.bids);
  const [standings, setStandings] = useState<Standing[]>(initial.standings);
  const format = initial.format;
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // How far this browser's clock is from the server's. Measured on mount and
  // re-measured on every RPC response, so a machine whose clock drifts mid-game
  // corrects itself. Both are read from the wall clock, so both are set in an
  // effect rather than during render.
  const offset = useRef(0);
  const [now, setNow] = useState(0);

  const applyTurn = useCallback((state: AuctionTurnRow) => {
    if (state.server_now) offset.current = Date.parse(state.server_now) - Date.now();
    setTurn({
      lotCount: state.lot_count ?? 0,
      currentLot: state.current_lot ?? 1,
      turnSeat: state.turn_seat,
      openerSeat: state.opener_seat ?? 0,
      turnDeadline: state.turn_deadline,
      phase: (state.phase ?? "lot_preview") as Turn["phase"],
      phaseDeadline: state.phase_deadline ?? null,
    });
  }, []);

  /**
   * Everything the screen holds, read again from the server.
   *
   * Realtime is the fast path, not the only path. The previous version applied
   * events and never checked its work, so a single dropped or missed payload
   * left the screen permanently wrong with nothing to say so — which is exactly
   * what playtesting hit. This is the reconciliation the old design was
   * missing; the callers below decide when it is worth running.
   */
  const refetch = useCallback(async () => {
    const supabase = getClient();
    const [state, lotRows, seatRows, bidRows, standingRows] = await Promise.all([
      supabase.rpc("auction_state", { p_match_id: matchId }),
      supabase.from("auction_lots").select("*").eq("match_id", matchId).order("seq"),
      supabase
        .from("auction_players")
        .select("*, profiles(display_name)")
        .eq("match_id", matchId)
        .order("seat"),
      supabase.from("auction_bids").select("*").eq("match_id", matchId).order("bid_seq"),
      supabase.from("match_players").select("*").eq("match_id", matchId),
    ]);

    if (state.data) applyTurn(state.data as AuctionTurnRow);
    if (lotRows.data) setLots(lotRows.data);
    if (bidRows.data) setBids(bidRows.data);
    if (standingRows.data) setStandings(standingRows.data);
    if (seatRows.data) {
      setPlayers(
        seatRows.data.map(({ profiles, ...seat }) => ({
          ...seat,
          display_name: profiles?.display_name ?? "Unknown player",
        })),
      );
    }
  }, [getClient, matchId, applyTurn]);

  // Realtime applies payloads to client state directly rather than refreshing
  // the server render — see LobbyRealtime for why the lobby does the opposite.
  useEffect(() => {
    let cleanup: (() => void) | null = null;
    let cancelled = false;

    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;

      const channel = supabase
        .channel(`match:${matchId}`)
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "auction_matches",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => applyTurn(payload.new as AuctionTurnRow),
        )
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "auction_lots", filter: `match_id=eq.${matchId}` },
          (payload) => {
            const lot = payload.new as Lot;
            setLots((prev) => prev.map((l) => (l.seq === lot.seq ? lot : l)));
          },
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "auction_players",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const seat = payload.new as Seat;
            setPlayers((prev) =>
              prev.map((p) => (p.user_id === seat.user_id ? { ...p, ...seat } : p)),
            );
          },
        )
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "auction_bids",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const bid = payload.new as Bid;
            setBids((prev) =>
              prev.some((b) => b.seq === bid.seq && b.bid_seq === bid.bid_seq)
                ? prev
                : [...prev, bid],
            );
          },
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "match_players",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const row = payload.new as Standing;
            setStandings((prev) => [...prev.filter((s) => s.user_id !== row.user_id), row]);
          },
        )
        // A rejoin is precisely when this client may have missed something, so
        // the state is read again rather than assumed to have kept up. Fires on
        // the first join too, which is a cheap duplicate of the server render.
        .subscribe((status) => {
          if (status === "SUBSCRIBED") void refetch();
        });

      cleanup = () => {
        void supabase.removeChannel(channel);
      };
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [matchId, applyTurn, refetch]);

  // The bar should move, so this ticks rather than counting seconds.
  useEffect(() => {
    offset.current = Date.parse(initial.serverNow) - Date.now();
    const tick = () => setNow(Date.now() + offset.current);
    tick();
    const id = setInterval(tick, TICK_MS);
    return () => clearInterval(id);
  }, [initial.serverNow]);

  const me = players.find((p) => p.user_id === viewerId) ?? null;
  const finished = turn.currentLot > turn.lotCount;
  const lot = lotAt(lots, turn.currentLot);

  const deadline = turn.turnDeadline ? Date.parse(turn.turnDeadline) : null;
  const phaseDeadline = turn.phaseDeadline ? Date.parse(turn.phaseDeadline) : null;
  // Null until the first tick has established what time the server thinks it is.
  const remainingMs =
    deadline === null || now === 0 ? null : Math.max(0, deadline - VISIBLE_SLACK_MS - now);
  const phaseRemainingMs = phaseDeadline === null || now === 0 ? null : Math.max(0, phaseDeadline - now);

  const act = useCallback(
    async (call: PromiseLike<{ data: AuctionTurnRow | null; error: { message: string } | null }>) => {
      setPending(true);
      setError(null);
      const { data, error: rpcError } = await call;
      if (rpcError) setError(MESSAGES[rpcError.message] ?? rpcError.message);
      else if (data) applyTurn(data);
      setPending(false);
    },
    [applyTurn],
  );

  // Every client that is NOT on the clock fires the expiry once its own
  // countdown has passed the deadline plus a little jitter. The player on the
  // clock gets first crack at acting, and the jitter stops four clients
  // stampeding the endpoint every single turn. Being wrong is free: the server
  // re-checks in its own time and does nothing if it disagrees.
  // Jitter now applies to every phase, not just bidding. The timer-only phases
  // used to fire at exactly the deadline across every client at once, which
  // both stampeded the endpoint and handed a marginally fast clock a guaranteed
  // no-op — and a no-op used to be final.
  const attempted = useRef(0);
  const jitter = useRef(0);
  useEffect(() => {
    jitter.current = 300 + Math.random() * 500;
    attempted.current = 0;
  }, [turn.currentLot, turn.turnSeat, turn.turnDeadline, turn.phase, turn.phaseDeadline]);

  useEffect(() => {
    const activeDeadline = deadline ?? phaseDeadline;
    if (activeDeadline === null || finished || now === 0) return;
    if (turn.phase === "bidding" && me && turn.turnSeat === me.seat) return;
    if (now < activeDeadline + jitter.current) return;
    if (now - attempted.current < RETRY_MS) return;
    attempted.current = now;

    void getClient()
      .rpc("expire_turn", { p_match_id: matchId })
      .then(({ data }) => data && applyTurn(data));
  }, [
    now,
    deadline, phaseDeadline,
    finished,
    me,
    matchId,
    getClient,
    applyTurn,
    turn.turnSeat,
    turn.phase,
  ]);

  // The watchdog. Expiry above is the mechanism; this is the admission that it
  // might not have worked — because this tab was backgrounded and its interval
  // throttled, because a realtime payload never arrived, or because the player
  // on the clock is the one client that deliberately never fires expiry. It
  // only runs once a deadline is well past, so a healthy game never reaches it.
  const reconciled = useRef(0);
  useEffect(() => {
    const activeDeadline = deadline ?? phaseDeadline;
    if (activeDeadline === null || finished || now === 0) return;
    if (now < activeDeadline + STALE_MS) return;
    if (now - reconciled.current < STALE_MS) return;
    reconciled.current = now;
    void refetch();
  }, [now, deadline, phaseDeadline, finished, refetch]);

  // Coming back to a tab is the other moment this screen is likely to be wrong:
  // background throttling means the clock above may have barely run at all.
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === "visible") void refetch();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [refetch]);

  if (finished) {
    return (
      <Screen displayName={displayName}>
        <FinalScreen
          lots={lots}
          players={players}
          standings={standings}
          viewerId={viewerId}
          roomCode={roomCode}
          format={format}
        />
      </Screen>
    );
  }

  if (!lot) {
    return (
      <Screen displayName={displayName}>
        <p className="text-sm text-fg-muted">Waiting for the next lot…</p>
      </Screen>
    );
  }

  const price = standingPrice(bids, lot.seq);
  const holder = highBidder(bids, lot.seq);
  const filled = me ? filledSlots(lots, me.user_id) : { QB: 0, RB: 0, WR: 0, TE: 0, FLEX: 0 };
  const passed = me ? hasPassed(bids, lot.seq, me.user_id) : false;
  const onClock = players.find((p) => p.seat === turn.turnSeat) ?? null;
  const phase = viewerPhase(turn, me?.seat ?? null);
  const blocked = me
    ? blockedReason({ lot, me, turnSeat: turn.turnSeat, filled, format, passed, price })
    : "not_your_turn";

  return (
    <Screen displayName={displayName} workspace>
      <LotStrip lots={lots} players={players} turn={turn} phase={phase} />
      {/* Stacked below 1024px, side by side at and above it. The mobile row
          template is the whole of story 8: the Lot is sized to its content and
          never compressed, and the Table takes what is left and scrolls inside
          itself. Without it both rows are auto and a four-seat table pushes the
          live auction off the screen. */}
      <div className="grid min-h-0 flex-1 grid-rows-[auto_minmax(6rem,1fr)] gap-3 lg:grid-cols-[minmax(0,1.1fr)_minmax(22rem,.9fr)] lg:grid-rows-1">
      <section className="flex min-h-0 flex-col gap-2" aria-label="The lot">
      {format ? (
        <p aria-label="Auction format" className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          {format.scoringMode === "season_total" ? "season total" : format.scoringMode} · {format.rosterPreset} · {format.qbSlots + format.rbSlots + format.wrSlots + format.teSlots + format.flexSlots} slots · ${format.purse} purse
        </p>
      ) : null}

      {/* The lot. Red top edge, because there is concealed information behind
          it — which is the rule Card already documents. */}
      <Card className="flex min-h-0 flex-1 flex-col">
        {/* The portrait band is the Lot's only flexible-height element, and it
            keeps its height whether or not a shot exists — a player nflverse
            has no picture for must not change the geometry under a live clock. */}
        <div className="min-h-24 flex-1 border-b border-dashed border-[#c7bfac] bg-panel-shade">
          {lot.headshot_url ? (
            <img
              src={lot.headshot_url}
              alt=""
              className="h-full w-full object-contain object-bottom [mask-image:linear-gradient(to_bottom,#000_58%,transparent_96%)]"
            />
          ) : null}
        </div>
        <CardTitle>{lot.display_name}</CardTitle>
        <CardMeta>{matchupLine(lot)}</CardMeta>
      </Card>

      {/* The payoff occupies the concealed surface rather than arriving as a
          second card. Its face is hidden from assistive technology; the one
          status sentence in PointsReveal is the complete announcement. */}
      {phase === "sold" ? (
        <PointsReveal lot={lot} />
      ) : (
        <Concealed label="Fantasy points, hidden until this lot is won" className="px-3.5 py-3">
          <div className="relative flex items-baseline justify-between gap-3">
            <span className="font-mono text-[10px] tracking-[0.15em] text-panel uppercase">
              Fantasy points
            </span>
            <span className="font-slab text-lg leading-none -skew-x-7 text-panel">? ? ?</span>
          </div>
        </Concealed>
      )}

      {me ? (
        <BidBar
          phase={phase}
          price={price}
          budget={me.budget}
          remainingMs={phase === "bidding_self" || phase === "bidding_other" ? remainingMs : phaseRemainingMs}
          onClock={onClock}
          isMine={phase === "bidding_self"}
          blocked={blocked}
          pending={pending}
          error={error}
          slot={slotFor(lot)}
          onRaise={(amount) => act(getClient().rpc("place_bid", { p_match_id: matchId, p_amount: amount }))}
          onPass={() => act(getClient().rpc("pass_lot", { p_match_id: matchId }))}
        />
      ) : <p className="min-h-17 text-sm text-fg-muted">You&apos;re watching this one.</p>}
      </section>

      <aside className="min-h-0 overflow-y-auto" aria-label="The table">
      <header className="flex items-baseline justify-between gap-3"><p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">The table</p><p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">Lot {turn.currentLot}</p></header>
      <PlayerRail
        players={players}
        lots={lots}
        viewerId={viewerId}
        turnSeat={turn.turnSeat}
        holder={holder}
        passedSeats={players
          .filter((p) => hasPassed(bids, lot.seq, p.user_id))
          .map((p) => p.seat)}
        soldLot={phase === "sold" ? lot : null}
        format={format}
      />
      </aside></div>
    </Screen>
  );
}

/** The shape auction_turn arrives in, from an RPC or from a replicated row. */
type AuctionTurnRow = {
  lot_count: number | null;
  current_lot: number | null;
  turn_seat: number | null;
  opener_seat: number | null;
  turn_deadline: string | null;
  phase?: string | null;
  phase_deadline?: string | null;
  server_now?: string | null;
};

function Screen({
  displayName,
  children,
  workspace = false,
}: {
  displayName: string | null;
  children: React.ReactNode;
  workspace?: boolean;
}) {
  return (
    <>
      <TopBar displayName={displayName} />
      {/* One column, thumb-width, because four people around a table are all
          holding phones. */}
      <main className={`mx-auto flex w-full flex-1 flex-col gap-4 px-5 pt-4 pb-4 ${workspace ? "min-h-0 max-w-6xl overflow-hidden lg:pb-5" : "max-w-md"}`}>
        {children}
      </main>
    </>
  );
}

/**
 * The auction's memory. The server already returns every dealt row to every
 * match member, so it is safe to show those identities here; fantasy points
 * remain the information withheld until a lot resolves. The length must come
 * from the turn, not the dealt rows, so undealt frames never need an identity.
 */
function LotStrip({
  lots,
  players,
  turn,
  phase,
}: {
  lots: Lot[];
  players: Player[];
  turn: Turn;
  phase: ReturnType<typeof viewerPhase>;
}) {
  const rail = useRef<HTMLOListElement>(null);
  const current = useRef<HTMLLIElement>(null);

  // The board moves inside its own rail: no page jump, just a gentle reminder
  // that the previous lot has become part of the table's shared memory.
  useEffect(() => {
    const strip = rail.current;
    const liveCell = current.current;
    if (!strip || !liveCell) return;
    strip.scrollTo({
      behavior: "smooth",
      left: liveCell.offsetLeft - (strip.clientWidth - liveCell.offsetWidth) / 2,
    });
  }, [turn.currentLot]);

  return (
    <ol
      ref={rail}
      aria-label="Auction board"
      className="flex shrink-0 gap-1.5 overflow-x-auto scroll-smooth pb-1 [scrollbar-width:thin]"
    >
      {Array.from({ length: turn.lotCount }, (_, index) => {
        const seq = index + 1;
        if (seq === turn.currentLot) {
          return <CurrentBoardCell key={seq} ref={current} seq={seq} lotCount={turn.lotCount} phase={phase} />;
        }

        const settled = lots.find((candidate) => candidate.seq === seq) ?? null;
        return settled && seq < turn.currentLot ? (
          <SettledBoardCell key={seq} lot={settled} players={players} />
        ) : (
          <UndealtBoardCell key={seq} seq={seq} />
        );
      })}
    </ol>
  );
}

const BOARD_CELL = "h-36 shrink-0 rounded border px-2 py-1.5";

function SettledBoardCell({ lot, players }: { lot: Lot; players: Player[] }) {
  const winner = players.find((player) => player.user_id === lot.winner_id) ?? null;
  const price = lot.price === null ? "no price" : `$${lot.price}`;
  const winnerCopy = winner ? `won by ${winner.display_name}` : "no winner";

  return (
    <li
      aria-label={`Lot ${lot.seq}, ${lot.display_name}, ${lot.slot ?? "unfilled"}, ${price}, ${winnerCopy}`}
      className={`${BOARD_CELL} flex w-36 flex-col border-line bg-surface-raised`}
    >
      <p className="flex items-baseline justify-between gap-1 font-mono text-[11px] leading-none text-fg-muted uppercase">
        <span>{lot.slot ?? "—"}</span>
        <span className="font-bold text-fg tabular-nums">{lot.price === null ? "—" : `$${lot.price}`}</span>
      </p>
      <span className="mx-auto mt-2 block h-8 w-8 shrink-0 overflow-hidden rounded-full bg-panel-shade">
        {lot.headshot_url ? <img src={lot.headshot_url} alt="" className="h-full w-full object-cover object-top" /> : null}
      </span>
      <p className="mt-1.5 truncate text-center font-slab text-[12px] leading-none -skew-x-7 uppercase">{lot.display_name}</p>
      <p className="mt-1.5 truncate text-center font-mono text-[11px] leading-none text-fg-muted uppercase">{lotIdentityLine(lot)}</p>
      <p className="mt-auto truncate font-mono text-[11px] leading-none text-fg-muted uppercase">
        {winner?.display_name ?? "No bids"}
      </p>
    </li>
  );
}

function CurrentBoardCell({
  seq,
  lotCount,
  phase,
  ref,
}: {
  seq: number;
  lotCount: number;
  phase: ReturnType<typeof viewerPhase>;
  ref: React.Ref<HTMLLIElement>;
}) {
  return (
    <li
      ref={ref}
      aria-current="step"
      className={`${BOARD_CELL} flex w-52 flex-col justify-center border-panel/45 bg-panel/10 px-3`}
    >
      <p className="font-slab text-xl leading-none -skew-x-7 uppercase">
        Lot {seq}
        <span className="ml-1.5 font-mono text-[11px] tracking-[0.1em] text-fg-muted">/ {lotCount}</span>
      </p>
      <p className="mt-2 font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase">
        {phase === "lot_preview" ? "Coming up" : phase === "sold" ? "Sold" : "On the clock"}
      </p>
    </li>
  );
}

function UndealtBoardCell({ seq }: { seq: number }) {
  return (
    <li
      aria-label={`Lot ${seq}, not yet dealt`}
      className={`${BOARD_CELL} flex w-36 flex-col items-center justify-center gap-2 border-dashed border-line bg-transparent`}
    >
      <span aria-hidden className="block h-8 w-8 rounded-full border border-dashed border-line" />
      <span className="font-mono text-[11px] leading-none text-fg-muted tabular-nums">{seq}</span>
    </li>
  );
}

/**
 * The payoff is the concealed surface turning over, not a second card. The
 * visible face must stay out of the accessibility tree: the status sentence
 * gives screen-reader users one complete, ordered announcement instead.
 */
function PointsReveal({ lot }: { lot: Lot }) {
  return (
    <section aria-label={`Lot ${lot.seq}, revealed`}>
      <div aria-hidden className="animate-points-reveal flex items-baseline justify-between gap-3 rounded-card bg-panel px-3.5 py-3 text-panel-fg shadow-card">
        <span className="font-mono text-[10px] tracking-[0.15em] text-panel-muted uppercase">
          Fantasy points
        </span>
        <span className="min-w-0 font-slab text-lg leading-none -skew-x-7 tabular-nums">
          {fmt(lot.points)}
        </span>
      </div>
      <p role="status" className="sr-only">{lot.display_name} reveals {fmt(lot.points)} fantasy points.</p>
    </section>
  );
}

/**
 * Everyone's budget and running total, always on screen, which is what lets a
 * player tell whether they are chasing or protecting. Rosters ride along so you
 * can read what the others still need.
 */
function PlayerRail({
  players,
  lots,
  viewerId,
  turnSeat,
  holder,
  passedSeats,
  soldLot,
  format,
}: {
  players: Player[];
  lots: Lot[];
  viewerId: string;
  turnSeat: number | null;
  holder: string | null;
  passedSeats: number[];
  soldLot: Lot | null;
  format: AuctionFormat | null;
}) {
  return (
    <ul className="flex flex-col gap-2">
      {players.map((player) => {
        const acting = player.seat === turnSeat;
        const total = revealedTotal(lots, player.user_id);

        return (
          <li
            key={player.user_id}
            className={`rounded border px-3 py-2.5 transition-colors ${
              soldLot?.winner_id === player.user_id ? "border-panel bg-panel/10 motion-safe:animate-sold-once" : acting ? "border-panel/45 bg-surface-raised" : "border-line bg-transparent"
            }`}
          >
            <div className="flex items-baseline justify-between gap-3">
              <span className="truncate font-slab text-[15px] leading-none -skew-x-7 uppercase">
                {player.display_name}
                {player.user_id === viewerId ? (
                  <span className="ml-1.5 font-mono text-[9px] tracking-[0.13em] text-fg-muted">
                    YOU
                  </span>
                ) : null}
              </span>
              <span className="shrink-0 font-mono text-[11px] text-fg tabular-nums">
                ${player.budget}
                <span className="ml-2 text-fg-muted">{fmt(total)} pts</span>
              </span>
            </div>

            <div className="mt-2 flex items-center justify-between gap-2">
              <Roster lots={lots} userId={player.user_id} format={format} highlightSlot={soldLot?.winner_id === player.user_id ? soldLot.slot : null} />
              <span className="shrink-0 font-mono text-[9px] tracking-[0.13em] text-fg-muted uppercase">
                {acting
                  ? "on the clock"
                  : holder === player.user_id
                    ? "high bid"
                    : passedSeats.includes(player.seat)
                      ? "passed"
                      : ""}
              </span>
            </div>
          </li>
        );
      })}
    </ul>
  );
}

/** Filled slots show what they hold. Unfilled ones are a dashed gap — an empty
 *  slot is absent, not withheld, and the concealed weave is reserved for the
 *  fantasy points, which exist and are being kept from you. */
function Roster({ lots, userId, format, highlightSlot = null }: { lots: Lot[]; userId: string; format: AuctionFormat | null; highlightSlot?: string | null }) {
  const slots = rosterSlots(format);
  const wonBySlot = (slot: Slot) => lots.filter((lot) => lot.winner_id === userId && lot.slot === slot);
  return (
    <ul className="flex gap-1">
      {slots.map(({ slot, index, label }) => {
        const won = wonBySlot(slot)[index - 1] ?? null;

        return (
          <li key={`${slot}-${index}`}>
            {won ? (
              <span
                aria-label={`${label} slot, ${won.display_name}, ${fmt(won.points)} points`}
                className={`flex h-7 min-w-11 items-center justify-center rounded-[3px] bg-panel px-1.5 font-mono text-[9px] text-panel-fg tabular-nums ${highlightSlot === slot ? "ring-2 ring-panel motion-safe:animate-sold-once" : ""}`}
              >
                {label}<span className="hidden lg:inline"> · {won.display_name}</span> {fmt(won.points)}
              </span>
            ) : (
              <span aria-label={`${label} slot, empty`} className="flex h-7 min-w-11 items-center justify-center rounded-[3px] border border-dashed border-fg-muted/70 px-1.5 font-mono text-[9px] tracking-[0.1em] text-fg-muted">{label}</span>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The controls. Pinned to the bottom of the column so the thumb never travels,
 * and sitting on --surface-raised, which the token file already annotates as
 * where a bid bar goes.
 *
 * A disabled control always says why. Four different situations produce the
 * same greyed button otherwise, and "you already have a quarterback" being
 * indistinguishable from a broken app is the difference between a rule and a
 * bug.
 */
function BidBar({
  phase,
  price,
  budget,
  remainingMs,
  onClock,
  isMine,
  blocked,
  pending,
  error,
  slot,
  onRaise,
  onPass,
}: {
  price: number;
  budget: number;
  remainingMs: number | null;
  onClock: Player | null;
  isMine: boolean;
  blocked: ReturnType<typeof blockedReason>;
  pending: boolean;
  onRaise: (amount: number) => void;
  onPass: () => void;
  phase: "lot_preview" | "bidding_self" | "bidding_other" | "sold";
  error: string | null;
  slot: string;
}) {
  const [customFor, setCustomFor] = useState<string | null>(null);
  const [amount, setAmount] = useState(String(price + 1));
  const input = useRef<HTMLInputElement>(null);
  const customButton = useRef<HTMLButtonElement>(null);
  const surface = useRef<HTMLDivElement>(null);
  const minimum = price + 1;
  // Keying the popover to the interaction rather than to a boolean is what
  // closes it on a turn change, a new price or a sale: the key it was opened
  // against simply stops being the current one.
  const interactionKey = `${phase}:${onClock?.seat ?? "none"}:${price}`;
  const custom = customFor === interactionKey;
  const actionable = phase === "bidding_self" && blocked === null && !pending;

  // Focus goes back where it came from on Escape and Cancel. It cannot on an
  // auto-close -- the phase change that closed the popover is the same one that
  // disabled the Custom button -- so those land on the control surface instead,
  // which keeps a keyboard user in the controls rather than at the document top.
  const dismissed = useRef(false);
  const wasOpen = useRef(false);
  const closeCustom = useCallback(() => { dismissed.current = true; setCustomFor(null); }, []);
  useEffect(() => {
    if (custom) { wasOpen.current = true; input.current?.focus(); return; }
    if (!wasOpen.current) return;
    wasOpen.current = false;
    if (dismissed.current) { dismissed.current = false; customButton.current?.focus(); }
    else surface.current?.focus();
  }, [custom]);
  const seconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);
  const live = phase === "bidding_self" || phase === "bidding_other";
  const fraction =
    remainingMs === null
      ? 0
      : Math.min(
          1,
          remainingMs /
            (live
              ? DURATION_MS.bidding - VISIBLE_SLACK_MS
              : DURATION_MS[phase === "sold" ? "sold" : "lot_preview"]),
        );
  const urgent = seconds !== null && seconds <= 3 && live;
  const invalid = !Number.isInteger(Number(amount)) || Number(amount) < minimum || Number(amount) > budget;

  return (
    <div
      ref={surface}
      tabIndex={-1}
      className="relative mt-auto border-t border-line bg-surface-raised px-3 pt-3 pb-3 outline-none"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          {phase === "lot_preview" ? "Bidding has not started" : phase === "sold" ? "Sold" : isMine ? "Your turn" : `${onClock?.display_name ?? "Someone"} is deciding`}
        </span>
        <span className={`font-mono tabular-nums ${isMine ? "font-slab text-3xl -skew-x-7" : "text-sm"}`}>
          {phase === "lot_preview" ? "—" : `$${price}`} <span className="font-mono text-sm text-fg-muted">· ${budget} left</span>
        </span>
      </div>

      {/* The countdown runs to 9.5s against a real 10s deadline, so a bid sent
          as the bar empties still has half a second of real deadline behind it.
          The slack sits behind the clock rather than in front of it, which is
          what keeps zero meaning zero. */}
      <div
        role="timer"
        aria-label={seconds === null ? "No timer" : `${seconds} seconds left`}
        className="mt-2 h-1 w-full overflow-hidden rounded-full bg-panel/15"
      >
        <div
          className={`h-full ${urgent ? "bg-hidden-text" : "bg-fg"}`}
          style={{ width: `${fraction * 100}%`, transition: `width ${TICK_MS}ms linear` }}
        />
      </div>
      <p className={`mt-1 text-right font-mono text-sm tabular-nums ${urgent ? "text-hidden-text" : "text-fg-muted"}`}>
        {seconds === null ? "—" : `${seconds}s`}
      </p>

      <div className="mt-2 flex gap-2">
        {INCREMENTS.map((increment) => (
          <Button
            key={increment}
            type="button"
            disabled={!actionable || !canAfford(price, budget, increment)}
            onClick={() => onRaise(price + increment)}
          >
            +${increment}
          </Button>
        ))}
        <Button ref={customButton} type="button" disabled={!actionable} onClick={() => { setAmount(String(minimum)); setCustomFor(interactionKey); }}>
          Custom
        </Button>
      </div>
      <p role={error ? "alert" : undefined} className={`mt-2 min-h-5 text-xs leading-5 ${error ? "text-hidden-text" : "text-fg-muted"}`}>
        {error ?? (phase === "lot_preview" ? "This player enters the auction." : phase === "sold" ? "The next player is coming up." : blocked ? (blocked === "no_slot" ? `Your ${slot} slots are full.` : BLOCKED_TEXT[blocked]) : !canAfford(price, budget, INCREMENTS[1]) ? `You can only raise by $${INCREMENTS[0]}.` : `A win fills your open ${slot}.`)}
        {phase === "bidding_self" && <button type="button" onClick={onPass} className="float-right text-fg-muted underline underline-offset-2">Pass</button>}
      </p>
      {custom && (
        <form
          role="dialog"
          aria-label="Custom bid"
          className="absolute right-3 bottom-3 left-3 rounded-card bg-panel p-3 text-panel-fg shadow-card"
          onSubmit={(event) => { event.preventDefault(); if (!invalid) onRaise(Number(amount)); }}
          onKeyDown={(event) => { if (event.key === "Escape") { event.preventDefault(); closeCustom(); } }}
        >
          <label className="block font-mono text-[10px] tracking-[.13em] text-panel-muted uppercase">Custom bid
            <input ref={input} value={amount} onChange={(event) => setAmount(event.target.value)} type="number" min={minimum} max={budget} step="1" inputMode="numeric" className="mt-2 block w-full rounded border border-panel-muted bg-[#fffdf7] px-2 py-2 font-mono text-lg font-bold" />
          </label>
          <p className="mt-1 text-xs text-panel-muted">Minimum is ${minimum}. Your maximum is ${budget}.</p>
          <div className="mt-2 flex gap-2"><Button type="submit" variant="ink" fullWidth={false} disabled={invalid || pending}>Bid ${amount}</Button><button type="button" onClick={closeCustom} className="text-xs text-panel-muted underline">Cancel</button></div>
        </form>
      )}
    </div>
  );
}

/** Names a winner, so the game ends rather than merely stopping. */
function FinalScreen({
  lots,
  players,
  standings,
  viewerId,
  roomCode,
  format,
}: {
  lots: Lot[];
  players: Player[];
  standings: Standing[];
  viewerId: string;
  roomCode: string | null;
  format: AuctionFormat | null;
}) {
  const ranked = byPlacement(standings);
  const nameOf = (userId: string) =>
    players.find((p) => p.user_id === userId)?.display_name ?? "Unknown player";
  const winners = ranked.filter((s) => s.placement === 1);

  return (
    <>
      <header className="flex flex-col gap-2 pt-4">
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          Final
        </p>
        <h1 className="font-slab text-3xl leading-none -skew-x-7 uppercase">
          {winners.length === 0
            ? "Game over"
            : winners.length === 1
              ? `${nameOf(winners[0].user_id)} wins`
              : `${winners.map((w) => nameOf(w.user_id)).join(" & ")} tie`}
        </h1>
      </header>

      <ul className="flex flex-col gap-2.5">
        {ranked.map((standing) => (
          <li key={standing.user_id}>
            <Card edge={false}>
              <div className="flex items-baseline justify-between gap-3 px-3 pt-2.5 pb-1">
                <span className="font-slab text-xl leading-none -skew-x-7 uppercase">
                  <span className="mr-2 font-mono text-[11px] text-panel-muted tabular-nums">
                    {standing.placement}
                  </span>
                  {nameOf(standing.user_id)}
                  {standing.user_id === viewerId ? (
                    <span className="ml-1.5 font-mono text-[9px] tracking-[0.13em] text-panel-muted">
                      YOU
                    </span>
                  ) : null}
                </span>
                <span className="font-mono text-sm font-bold text-panel-fg tabular-nums">
                  {fmt(standing.raw_score)}
                </span>
              </div>
              <div className="px-3 pb-3">
                <RosterFinal lots={lots} userId={standing.user_id} format={format} />
              </div>
            </Card>
          </li>
        ))}
      </ul>

      <Link
        href={roomCode ? `/lobby/${roomCode}` : "/"}
        className="mt-2 text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
      >
        {roomCode ? "Back to the room" : "Back home"}
      </Link>
    </>
  );
}

/** The full roster, so there is something to argue about afterwards. */
function RosterFinal({ lots, userId, format }: { lots: Lot[]; userId: string; format: AuctionFormat | null }) {
  const won = lots.filter((l) => l.winner_id === userId);

  return (
    <dl className="flex flex-col gap-1 border-t border-dashed border-[#c7bfac] pt-2 font-mono text-[10px] text-panel-muted">
      {rosterSlots(format).map(({ slot, index, label }) => {
        const lot = won.filter((l) => l.slot === slot)[index - 1] ?? null;
        return (
          <div key={`${slot}-${index}`} className="flex items-baseline justify-between gap-2">
            <dt className="w-10 shrink-0 uppercase">{label}</dt>
            <dd className="flex-1 truncate text-panel-fg">
              {lot ? `${lot.display_name} · ${lot.season}${lot.week === null ? ` · ${lot.team}` : ` wk ${lot.week}`}` : "—"}
            </dd>
            <dd className="shrink-0 font-bold text-panel-fg tabular-nums">
              {lot ? `$${lot.price} · ${fmt(lot.points)}` : ""}
            </dd>
          </div>
        );
      })}
    </dl>
  );
}

/** Points arrive as numeric strings; one decimal is how the game reads them. */
function fmt(value: string | number | null): string {
  if (value === null) return "—";
  return Number(value).toFixed(1);
}
