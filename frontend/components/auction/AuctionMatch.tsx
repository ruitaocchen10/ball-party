"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";

import { TopBar } from "@/components/layout/TopBar";
import { Button } from "@/components/ui/Button";
import { Card, CardMeta, CardStats, CardTitle, Stat } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import {
  BLOCKED_TEXT,
  INCREMENTS,
  SLOTS,
  blockedReason,
  byPlacement,
  canAfford,
  chancesLeft,
  filledSlots,
  hasPassed,
  highBidder,
  lotAt,
  matchupLine,
  revealedTotal,
  standingPrice,
  type Bid,
  type Lot,
  type Player,
  type Seat,
  type Standing,
  type Turn,
} from "@/lib/auction/board";
import { createClient } from "@/lib/supabase/client";

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

/** The server's real deadline is ten seconds; the visible clock stops short. */
const VISIBLE_SLACK_MS = 500;
const TICK_MS = 100;

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
  bad_increment: "You can only raise by $1 or $5.",
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
  complete: boolean;
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
  const supabase = useMemo(() => createClient(), []);

  const [turn, setTurn] = useState<Turn>(initial.turn);
  const [lots, setLots] = useState<Lot[]>(initial.lots);
  const [players, setPlayers] = useState<Player[]>(initial.players);
  const [bids, setBids] = useState<Bid[]>(initial.bids);
  const [standings, setStandings] = useState<Standing[]>(initial.standings);
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
    });
  }, []);

  // Realtime applies payloads to client state directly rather than refreshing
  // the server render — see LobbyRealtime for why the lobby does the opposite.
  useEffect(() => {
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
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [supabase, matchId, applyTurn]);

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
  // Null until the first tick has established what time the server thinks it is.
  const remainingMs =
    deadline === null || now === 0 ? null : Math.max(0, deadline - VISIBLE_SLACK_MS - now);

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
  const fired = useRef<string | null>(null);
  const jitter = useRef(0);
  useEffect(() => {
    jitter.current = 300 + Math.random() * 500;
  }, [turn.currentLot, turn.turnSeat, turn.turnDeadline]);

  useEffect(() => {
    if (deadline === null || turn.turnSeat === null || finished || now === 0) return;
    if (me && turn.turnSeat === me.seat) return;
    if (now < deadline + jitter.current) return;

    const key = `${turn.currentLot}:${turn.turnSeat}:${turn.turnDeadline}`;
    if (fired.current === key) return;
    fired.current = key;

    void supabase
      .rpc("expire_turn", { p_match_id: matchId })
      .then(({ data }) => data && applyTurn(data));
  }, [
    now,
    deadline,
    finished,
    me,
    matchId,
    supabase,
    applyTurn,
    turn.currentLot,
    turn.turnSeat,
    turn.turnDeadline,
  ]);

  if (finished) {
    return (
      <Screen displayName={displayName}>
        <FinalScreen
          lots={lots}
          players={players}
          standings={standings}
          viewerId={viewerId}
          roomCode={roomCode}
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
  const filled = me ? filledSlots(lots, me.user_id) : new Set<string>();
  const passed = me ? hasPassed(bids, lot.seq, me.user_id) : false;
  const onClock = players.find((p) => p.seat === turn.turnSeat) ?? null;
  const blocked = me
    ? blockedReason({ lot, me, turnSeat: turn.turnSeat, filled, passed, price })
    : "not_your_turn";

  // The lot that just resolved. The reveal is one server write and current_lot
  // moves on in the same transaction, so the payoff would never be on screen if
  // the card only ever showed the lot being bid on.
  const lastResolved = lots
    .filter((l) => l.resolved_at !== null)
    .reduce<Lot | null>((latest, l) => (latest === null || l.seq > latest.seq ? l : latest), null);

  return (
    <Screen displayName={displayName}>
      <header className="flex items-baseline justify-between gap-3">
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          Lot {turn.currentLot} of {turn.lotCount}
        </p>
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          {lot.is_flex ? "Flex" : lot.position} {chancesLeft(lots, lot, turn.currentLot)} left
        </p>
      </header>

      {/* The lot. Red top edge, because there is concealed information behind
          it — which is the rule Card already documents. */}
      <Card>
        <CardTitle>{lot.display_name}</CardTitle>
        <CardMeta>{matchupLine(lot)}</CardMeta>
      </Card>

      {/* The fantasy points, which are not merely absent — they are being
          withheld, and the weave is how this product says so. */}
      <Concealed label="Fantasy points, hidden until this lot is won" className="px-3.5 py-3">
        <div className="relative flex items-baseline justify-between gap-3">
          <span className="font-mono text-[10px] tracking-[0.15em] text-panel/85 uppercase">
            Fantasy points
          </span>
          <span className="font-slab text-lg leading-none -skew-x-7 text-panel/90">? ? ?</span>
        </div>
      </Concealed>

      {lastResolved ? <Revealed lot={lastResolved} players={players} /> : null}

      <PlayerRail
        players={players}
        lots={lots}
        viewerId={viewerId}
        turnSeat={turn.turnSeat}
        holder={holder}
        passedSeats={players
          .filter((p) => hasPassed(bids, lot.seq, p.user_id))
          .map((p) => p.seat)}
      />

      {error ? (
        <p
          role="alert"
          className="rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
        >
          {error}
        </p>
      ) : null}

      {me ? (
        <BidBar
          price={price}
          budget={me.budget}
          remainingMs={remainingMs}
          onClock={onClock}
          isMine={turn.turnSeat === me.seat}
          blocked={blocked}
          pending={pending}
          onRaise={(increment) =>
            act(supabase.rpc("place_bid", { p_match_id: matchId, p_increment: increment }))
          }
          onPass={() => act(supabase.rpc("pass_lot", { p_match_id: matchId }))}
        />
      ) : (
        <p className="text-sm text-fg-muted">You&apos;re watching this one.</p>
      )}
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
  server_now?: string | null;
};

function Screen({
  displayName,
  children,
}: {
  displayName: string | null;
  children: React.ReactNode;
}) {
  return (
    <>
      <TopBar displayName={displayName} />
      {/* One column, thumb-width, because four people around a table are all
          holding phones. */}
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col gap-4 px-5 pt-6 pb-4">
        {children}
      </main>
    </>
  );
}

/**
 * What the last lot turned out to be. This is the payoff: it appears at the
 * instant the lot resolves, carrying the number everybody was guessing at.
 */
function Revealed({ lot, players }: { lot: Lot; players: Player[] }) {
  const winner = players.find((p) => p.user_id === lot.winner_id) ?? null;

  return (
    <section aria-label={`Lot ${lot.seq}, revealed`} className="flex flex-col gap-1.5">
      <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
        Lot {lot.seq} · revealed
      </p>
      <Card edge={false}>
        <CardTitle className="text-xl">{lot.display_name}</CardTitle>
        <CardMeta>{matchupLine(lot)}</CardMeta>
        <CardStats>
          <Stat label="Fpts" value={fmt(lot.points)} />
          <Stat label="Won by" value={winner ? winner.display_name : "Nobody"} />
          <Stat label="Price" value={lot.price === null ? "—" : `$${lot.price}`} />
        </CardStats>
      </Card>
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
}: {
  players: Player[];
  lots: Lot[];
  viewerId: string;
  turnSeat: number | null;
  holder: string | null;
  passedSeats: number[];
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
              acting ? "border-panel/45 bg-surface-raised" : "border-line bg-transparent"
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
              <Roster lots={lots} userId={player.user_id} />
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

/** Filled slots show what they hold. Unfilled ones are concealed, the same as
 *  an open spot in the lobby: red means the thing is not there yet. */
function Roster({ lots, userId }: { lots: Lot[]; userId: string }) {
  return (
    <ul className="flex gap-1">
      {SLOTS.map((slot) => {
        const won = lots.find((l) => l.winner_id === userId && l.slot === slot) ?? null;

        return (
          <li key={slot}>
            {won ? (
              <span className="flex h-7 min-w-11 items-center justify-center rounded-[3px] bg-panel px-1.5 font-mono text-[9px] text-panel-fg tabular-nums">
                {slot} {fmt(won.points)}
              </span>
            ) : (
              <Concealed
                label={`${slot} slot, not filled`}
                className="flex h-7 min-w-11 items-center justify-center px-1.5"
              >
                <span className="relative font-mono text-[9px] tracking-[0.1em] text-panel/85">
                  {slot}
                </span>
              </Concealed>
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
  price,
  budget,
  remainingMs,
  onClock,
  isMine,
  blocked,
  pending,
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
  onRaise: (increment: number) => void;
  onPass: () => void;
}) {
  const seconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);
  const fraction = remainingMs === null ? 0 : Math.min(1, remainingMs / (10_000 - VISIBLE_SLACK_MS));

  return (
    <div className="sticky bottom-0 -mx-5 mt-auto border-t border-line bg-surface-raised px-5 pt-3 pb-4">
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          {isMine ? "Your turn" : `${onClock?.display_name ?? "Someone"} is deciding`}
        </span>
        <span className="font-mono text-sm text-fg tabular-nums">
          ${price} <span className="text-fg-muted">· ${budget} left</span>
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
          className="h-full bg-hidden-text"
          style={{ width: `${fraction * 100}%`, transition: `width ${TICK_MS}ms linear` }}
        />
      </div>

      <div className="mt-3 flex gap-2">
        {INCREMENTS.map((increment) => (
          <Button
            key={increment}
            type="button"
            disabled={pending || blocked !== null || !canAfford(price, budget, increment)}
            onClick={() => onRaise(increment)}
          >
            +${increment}
          </Button>
        ))}
        <Button type="button" variant="ghost" disabled={pending || blocked !== null} onClick={onPass}>
          Pass
        </Button>
      </div>

      {blocked ? (
        <p className="mt-2 font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          {BLOCKED_TEXT[blocked]}
        </p>
      ) : !canAfford(price, budget, INCREMENTS[1]) ? (
        <p className="mt-2 font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          You can only raise by ${INCREMENTS[0]}
        </p>
      ) : null}
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
}: {
  lots: Lot[];
  players: Player[];
  standings: Standing[];
  viewerId: string;
  roomCode: string | null;
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
                <RosterFinal lots={lots} userId={standing.user_id} />
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
function RosterFinal({ lots, userId }: { lots: Lot[]; userId: string }) {
  const won = lots.filter((l) => l.winner_id === userId);

  return (
    <dl className="flex flex-col gap-1 border-t border-dashed border-[#c7bfac] pt-2 font-mono text-[10px] text-panel-muted">
      {SLOTS.map((slot) => {
        const lot = won.find((l) => l.slot === slot) ?? null;
        return (
          <div key={slot} className="flex items-baseline justify-between gap-2">
            <dt className="w-10 shrink-0 uppercase">{slot}</dt>
            <dd className="flex-1 truncate text-panel-fg">
              {lot ? `${lot.display_name} · ${lot.season} wk ${lot.week}` : "—"}
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
