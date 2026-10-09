"use client";

import { AnimatePresence, motion } from "motion/react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode, type Ref } from "react";
import Link from "next/link";

import { FinalStandings, type FinalStandingsRow } from "@/components/runtime/game-runtime/FinalStandings";
import { PauseBanner } from "@/components/runtime/game-runtime/PauseBanner";
import { PauseButton } from "@/components/runtime/game-runtime/PauseButton";
import { PostGameControls } from "@/components/runtime/game-runtime/PostGameControls";
import { PostGameNavigation } from "@/components/runtime/game-runtime/PostGameNavigation";
import { Reveal } from "@/components/foundation/ui-kit/Reveal";
import { SlotReel } from "@/components/foundation/ui-kit/SlotReel";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Concealed } from "@/components/foundation/ui-kit/Concealed";
import { abbreviate, MatchStrip, StripCell, StripCellAvatar, StripCellCaption, StripCellMedia, StripCellName, StripCellTextColumn, StripCellTitle, StripCellTop } from "@/components/foundation/ui-kit/MatchStrip";
import { dropdown } from "@/lib/foundation/ui-kit/motion";
import {
  BLOCKED_TEXT,
  INCREMENTS,
  blockedReason,
  byPlacement,
  canAfford,
  eligibleFor,
  filledSlots,
  hasPassed,
  hasSubmittedSealedBid,
  highBidder,
  lotAt,
  upsertLot,
  myScoutHint,
  mySealedBid,
  revealedTotal,
  rosterSlots,
  standingPrice,
  targetSlotFor,
  tokensRemaining,
  viewerPhase,
  weeklyRevealTier,
  type Bid,
  type AuctionFormat,
  type Lot,
  type Player,
  type ScoutHint,
  type SealedBid,
  type SealedBidStatus,
  type Seat,
  type Standing,
  type Slot,
  type Turn,
  type AuctionPhase,
} from "@/lib/games/auction/board";
import { auctionLogoCode } from "@/lib/games/auction/teams";
import { LOT_REVEAL_MS, useLotReveal } from "@/lib/games/auction/useLotReveal";
import { createClient } from "@/lib/supabase/client";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";
import { TICK_MS, VISIBLE_SLACK_MS, useMatchClock } from "@/lib/runtime/game-runtime/useMatchClock";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

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

/**
 * The server's real deadline is longer than the visible clock, which stops
 * short so a bid sent as the bar empties still has real deadline behind it.
 * That slack, the repeat-with-jitter expiry polling and the reconciliation
 * triggers all live in the shared match clock now -- see its module doc for
 * the playtest that shape is fixing (three lots in one game took 81s, 127s
 * and 271s, because a client asked once and latched). DURATION_MS is the only
 * piece that stays here: it is the bid bar's own fraction-of-elapsed drawing,
 * mirroring the intervals in the migrations. The server remains the only
 * thing that decides when a phase is actually over.
 */
const DURATION_MS: Record<Turn["phase"], number> = {
  lot_preview: 5_000,
  bidding: 20_000,
  sold: 5_000,
  sealed: 20_000,
};

/** Match Sabotage Draft's shot-clock convention once a bid window is tight. */
const TENTHS_THRESHOLD_MS = 5_000;

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
  no_pass_tokens: "You're out of pass tokens, so this one's yours.",
  no_scout_tokens: "You're out of scouting tokens.",
  lot_already_resolved: "This lot's points are already revealed.",
  no_seal_tokens: "You're out of sealed-bid tokens.",
  sealing_not_available: "This lot can't be sealed right now.",
  bidding_already_underway: "Someone's already bid on this lot, so it can't be sealed.",
  seal_needs_two_bidders: "Nobody else can bid on this lot, so sealing it wouldn't change anything.",
  sealed_bidding_not_open: "Sealed bidding on this lot has already closed.",
  already_submitted: "You've already submitted your sealed bid.",
  match_not_playing: "This game isn't accepting moves right now.",
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
  era?: { seasonMin: number; seasonMax: number; minSpan: number } | null;
  /** Only ever the viewer's own rows -- see ScoutHint's own doc comment. */
  scoutHints?: ScoutHint[];
  /** Only ever the viewer's own rows -- see SealedBid's own doc comment. */
  sealedBids?: SealedBid[];
  /** Presence, readable for every match member -- see SealedBidStatus. */
  sealedStatuses?: SealedBidStatus[];
};

export function AuctionMatch({
  matchId,
  viewerId,
  roomCode,
  isHost = false,
  paused = false,
  complete = false,
  initial,
}: {
  matchId: string;
  viewerId: string;
  roomCode: string | null;
  isHost?: boolean;
  paused?: boolean;
  complete?: boolean;
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
  const [scoutHints, setScoutHints] = useState<ScoutHint[]>(initial.scoutHints ?? []);
  const [sealedBids, setSealedBids] = useState<SealedBid[]>(initial.sealedBids ?? []);
  const [sealedStatuses, setSealedStatuses] = useState<SealedBidStatus[]>(initial.sealedStatuses ?? []);
  const format = initial.format;
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Scouting isn't a bidding action -- it has no turn to wait for -- so it
  // gets its own pending/error pair rather than sharing BidBar's, which
  // would otherwise disable raise/pass while a scout call is in flight and
  // show a scouting error in a status line about something else entirely.
  const [scoutPending, setScoutPending] = useState(false);
  const [scoutError, setScoutError] = useState<string | null>(null);
  const [isPaused, setIsPaused] = useState(paused);
  // Since 0090, the board can end before current_lot ever reaches lot_count
  // -- a match is over the moment every roster is full, not only when the
  // deck runs out. `finished` below has to know that independently of the
  // lot-count comparison it used to rely on alone, so this rides the same
  // live `matches` row this component already subscribes to for `isPaused`.
  const [isComplete, setIsComplete] = useState(complete);

  // Server time as of the most recently applied state. The shared match clock
  // measures how far this browser's clock is from the server's against it, so
  // a machine whose clock drifts mid-game keeps correcting itself. State
  // rather than a ref: applyTurn already has a setter for everything else it
  // updates, and this is one more.
  const [serverNow, setServerNow] = useState(initial.serverNow);

  const applyTurn = useCallback((state: AuctionTurnRow) => {
    if (state.server_now) setServerNow(state.server_now);
    setTurn({
      lotCount: state.lot_count ?? 0,
      currentLot: state.current_lot ?? 1,
      turnSeat: state.turn_seat,
      openerSeat: state.opener_seat ?? 0,
      freeFallbackSeat: state.free_fallback_seat ?? null,
      stuckSeat: state.stuck_seat ?? null,
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
    const [state, lotRows, seatRows, bidRows, standingRows, hintRows, sealedBidRows, sealedStatusRows] = await Promise.all([
      supabase.schema("auction").rpc("state", { p_match_id: matchId }),
      supabase.from("auction_lots").select("*").eq("match_id", matchId).order("seq"),
      supabase
        .from("auction_players")
        .select("*, profiles(display_name, avatar_url)")
        .eq("match_id", matchId)
        .order("seat"),
      supabase.from("auction_bids").select("*").eq("match_id", matchId).order("bid_seq"),
      supabase.from("match_players").select("*").eq("match_id", matchId),
      // RLS scopes this to the viewer's own rows -- see ScoutHint's doc comment.
      supabase.from("auction_scouting_hints").select("*").eq("match_id", matchId),
      // Also viewer-own only -- see SealedBid's doc comment.
      supabase.from("auction_sealed_bids").select("*").eq("match_id", matchId),
      // Presence, readable for every match member -- see SealedBidStatus.
      supabase.from("auction_sealed_bid_statuses").select("*").eq("match_id", matchId),
    ]);

    if (state.data) applyTurn(state.data as AuctionTurnRow);
    if (lotRows.data) setLots(lotRows.data);
    if (bidRows.data) setBids(bidRows.data);
    if (standingRows.data) setStandings(standingRows.data);
    if (hintRows.data) setScoutHints(hintRows.data);
    if (sealedBidRows.data) setSealedBids(sealedBidRows.data);
    if (sealedStatusRows.data) setSealedStatuses(sealedStatusRows.data);
    if (seatRows.data) {
      setPlayers(
        seatRows.data.map(({ profiles, ...seat }) => ({
          ...seat,
          display_name: profiles?.display_name ?? "Unknown player",
          avatar_url: profiles?.avatar_url ?? null,
        })),
      );
    }
  }, [getClient, matchId, applyTurn]);

  const me = players.find((p) => p.user_id === viewerId) ?? null;
  // Either signal alone is right at the moment its source updates; the two
  // can otherwise disagree for one tick after an early finish, since this is
  // a race between two different realtime subscriptions (auction_matches for
  // turn.currentLot, matches for isComplete) rather than one atomic update.
  const finished = turn.currentLot > turn.lotCount || isComplete;
  const lot = lotAt(lots, turn.currentLot);
  // A brief suspense beat before each lot's player appears, mirroring
  // sabotage draft's turn reveal -- the identity is already in `lots`, this
  // just paces when it's shown. Called unconditionally, above the early
  // returns below, per the Rules of Hooks.
  const { revealed: lotRevealed } = useLotReveal(String(turn.currentLot));

  // Bidding is the one phase a move can be sent in, so it is the one phase
  // the visible countdown ends early for; a finished match has no deadline
  // left to chase, whatever a stale turn record still says. Exactly one of
  // turnDeadline/phaseDeadline is ever set at a time -- the server sets the
  // former during bidding and the latter otherwise -- so there is always at
  // most one active deadline to hand the clock.
  const bidding = turn.phase === "bidding";
  const activeDeadline = finished ? null : (turn.turnDeadline ?? turn.phaseDeadline);
  // The player on the clock is the one client that cannot be trusted with
  // expiry: everyone else fires it, jittered, while they get first crack at
  // acting.
  const skipExpiry = bidding && !!me && turn.turnSeat === me.seat;

  const { remainingMs, reconcile } = useMatchClock({
    serverNow,
    deadline: activeDeadline,
    visibleSlackMs: bidding ? VISIBLE_SLACK_MS : 0,
    skipExpiry,
    paused: isPaused,
    expire: () =>
      getClient()
        .schema("auction")
        .rpc("expire_turn", { p_match_id: matchId })
        .then(({ data }) => {
          if (data) applyTurn(data as AuctionTurnRow);
        }),
    reconcile: refetch,
  });

  // The final screen is built from `lots`, so make sure it is the server's
  // full list at the moment the match ends rather than whatever realtime
  // happened to deliver.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- refetch's setState happens after an await, once the match-end snapshot comes back, not synchronously in this effect body.
    if (finished) void refetch();
  }, [finished, refetch]);

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
            // Upsert, not just replace: a declined lot (Pass token) appends a
            // brand-new lot to the deck mid-match, and dropping that INSERT
            // left the board with no lot to show once play reached it.
            setLots((prev) => upsertLot(prev, lot));
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
          // RLS already scoped this row to the viewer's own before it ever
          // reached the socket (0159) -- an opponent's hint never arrives
          // here to filter out, there is simply no payload for it.
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "auction_scouting_hints",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const hint = payload.new as ScoutHint;
            setScoutHints((prev) =>
              prev.some((h) => h.seq === hint.seq && h.user_id === hint.user_id)
                ? prev
                : [...prev, hint],
            );
          },
        )
        .on(
          // Same shape as scouting hints above: RLS already scoped this to
          // the viewer's own bid before it reached the socket (0160).
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "auction_sealed_bids",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const sealedBid = payload.new as SealedBid;
            setSealedBids((prev) =>
              prev.some((b) => b.seq === sealedBid.seq && b.user_id === sealedBid.user_id)
                ? prev
                : [...prev, sealedBid],
            );
          },
        )
        .on(
          // Every match member receives this one -- it's presence, not the
          // amount (0160) -- so event:"*" covers the upsert this table's
          // one write path (`submit_sealed_bid`) uses.
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "auction_sealed_bid_statuses",
            filter: `match_id=eq.${matchId}`,
          },
          (payload) => {
            const status = payload.new as SealedBidStatus;
            setSealedStatuses((prev) =>
              prev.some((s) => s.seq === status.seq && s.user_id === status.user_id)
                ? prev.map((s) => (s.seq === status.seq && s.user_id === status.user_id ? status : s))
                : [...prev, status],
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
        .on(
          "postgres_changes",
          { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${matchId}` },
          (payload) => {
            const status = (payload.new as { status?: string }).status;
            setIsPaused(status === "paused");
            setIsComplete(status === "complete");
          },
        )
        // A rejoin is precisely when this client may have missed something, so
        // the state is read again rather than assumed to have kept up -- the
        // third of the match clock's three reconciliation triggers. Fires on
        // the first join too, which is a cheap duplicate of the server render.
        .subscribe((status) => {
          if (status === "SUBSCRIBED") reconcile();
        });

      cleanup = () => {
        void supabase.removeChannel(channel);
      };
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [matchId, applyTurn, reconcile]);

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

  const scoutLot = useCallback(async () => {
    setScoutPending(true);
    setScoutError(null);
    const { data, error: rpcError } = await getClient()
      .schema("auction")
      .rpc("use_scout_token", { p_match_id: matchId });
    if (rpcError) setScoutError(MESSAGES[rpcError.message] ?? rpcError.message);
    // The realtime INSERT subscription would eventually deliver the same
    // row, but the RPC already hands back the tier it just wrote -- no
    // reason to make the viewer wait a round trip to see their own answer.
    else if (typeof data === "string") {
      setScoutHints((prev) => [
        ...prev,
        { match_id: matchId, seq: turn.currentLot, user_id: viewerId, tier: data, created_at: new Date().toISOString() },
      ]);
    }
    setScoutPending(false);
  }, [getClient, matchId, turn.currentLot, viewerId]);

  // Both of these change turn state the same way a raise or a pass does
  // (phase moves to 'sealed', then eventually to 'sold'), so they share
  // `act`'s pending/error plumbing rather than getting their own the way
  // scoutLot above needed to -- scouting is the odd one out because it
  // never touches `turn` at all.
  const sealLot = useCallback(
    () => act(getClient().schema("auction").rpc("use_seal_token", { p_match_id: matchId })),
    [act, getClient, matchId],
  );
  const submitSealedBid = useCallback(
    (amount: number) => act(getClient().schema("auction").rpc("submit_sealed_bid", { p_match_id: matchId, p_amount: amount })),
    [act, getClient, matchId],
  );
  // Shared by BidBar's ordinary ghost Pass button and the pass token in the
  // token tray below -- a stuck decline is the same RPC as an ordinary pass,
  // just reached from a different control once the token moves there.
  const passLot = useCallback(
    () => act(getClient().schema("auction").rpc("pass_lot", { p_match_id: matchId })),
    [act, getClient, matchId],
  );

  if (finished) {
    return (
      <PageShell variant="narrow">
        <FinalScreen
          lots={lots}
          players={players}
          standings={standings}
          viewerId={viewerId}
          roomCode={roomCode}
          matchId={matchId}
          isHost={isHost}
          format={format}
          era={initial.era ?? null}
        />
      </PageShell>
    );
  }

  if (!lot) {
    return (
      <PageShell variant="game" locked>
        <p className="text-sm text-fg-muted">Waiting for the next lot…</p>
      </PageShell>
    );
  }

  const price = standingPrice(bids, lot.seq);
  const holder = highBidder(bids, lot.seq);
  const lotTeamLogo = auctionLogoCode(lot.team);
  const revealTier = weeklyRevealTier(lot);
  const filled = me ? filledSlots(lots, me.user_id) : { QB: 0, RB: 0, WR: 0, TE: 0, FLEX: 0 };
  const passed = me ? hasPassed(bids, lot.seq, me.user_id) : false;
  const onClock = players.find((p) => p.seat === turn.turnSeat) ?? null;
  const phase = viewerPhase(turn, me?.seat ?? null);
  const blocked = me
    ? blockedReason({ lot, me, lots, players, turnSeat: turn.turnSeat, format, passed, price })
    : "not_your_turn";
  const myHint = me ? myScoutHint(scoutHints, lot.seq, me.user_id) : null;
  const scoutAvailable = !!me && phase !== "sold" && !me.used_scout_token && tokensRemaining(format, me) > 0;
  const noBidsYet = !bids.some((b) => b.seq === lot.seq);
  // Sealing only makes sense pre-bid and with a real contest on the other
  // side -- the server re-checks both (0160), this just keeps the button
  // from inviting a refusal it could have predicted.
  const sealAvailable =
    !!me &&
    (phase === "bidding_self" || phase === "bidding_other") &&
    noBidsYet &&
    !me.used_seal_token &&
    tokensRemaining(format, me) > 0 &&
    players.filter((p) => eligibleFor(lot, lots, players, p.user_id, format)).length >= 2;
  const mySeal = me ? mySealedBid(sealedBids, lot.seq, me.user_id) : null;
  // Nobody else is live on this lot -- the board would hand it to the viewer
  // for $0 the moment they act. Declining it is what the pass token is for.
  const stuck = !!me && turn.stuckSeat === me.seat && price === 0;
  const passTokenAvailable = !!me && !me.used_pass_token && tokensRemaining(format, me) > 0;
  // A token's tray state is "used" the moment this screen has its own proof
  // of that -- a seat-row update can lag a beat behind the action that
  // caused it, the same reason the old Scout control kept its own hint
  // check instead of waiting on `used_scout_token` to come back over
  // realtime. Seal doesn't need the same guard: sealAvailable already drops
  // out the instant the phase itself moves to 'sealed'.
  const passState: TokenState = me?.used_pass_token ? "used" : stuck && passTokenAvailable ? "usable" : "inactive";
  const scoutState: TokenState = me?.used_scout_token || myHint ? "used" : scoutAvailable ? "usable" : "inactive";
  const sealState: TokenState = me?.used_seal_token ? "used" : sealAvailable ? "usable" : "inactive";

  return (
    <PageShell variant="game" locked>
      {isHost || isPaused ? (
        <div className="flex items-start justify-between gap-3">
          {isPaused ? <PauseBanner /> : <div />}
          {isHost ? <PauseButton matchId={matchId} paused={isPaused} /> : null}
        </div>
      ) : null}
      <LotStrip lots={lots} players={players} turn={turn} phase={phase} />
      {/* DOM order is the phone's decision order: understand the lot, decide
          what to do, then inspect the other seats. Desktop placement gives
          controls their own column without changing that reading order. */}
      <div className="grid min-h-0 flex-1 grid-rows-[auto_auto_minmax(6rem,1fr)] gap-3 lg:grid-cols-[minmax(15rem,.62fr)_minmax(0,1fr)_minmax(21rem,.95fr)] lg:grid-rows-1">
      <section className="flex min-h-0 flex-col gap-2 lg:col-start-2 lg:row-start-1" aria-label="The lot">
      {/* A portrait-forward featured card, borrowing Sabotage Draft's
          tenured-player treatment without confusing the lot's slot with a
          player rank. The concealed score remains its own auction-only beat. */}
      <div className="relative flex flex-none flex-col items-center border border-line bg-surface-raised px-4 py-5 text-center shadow-well">
        <span className="absolute top-3 left-3 font-slab text-xl leading-none text-fg uppercase">{lot.position}</span>
        {lotTeamLogo ? <TeamLogo code={lotTeamLogo} className="absolute top-3 right-3 h-8 w-8" /> : null}
        {/* A brief suspense beat before the lot's player appears, mirroring
            sabotage draft's turn reveal -- the name/portrait/matchup hold
            behind a "Revealing…" placeholder for useLotReveal's delay, then
            crossfade in. The slot badge and team logo above stay put; only
            the player's own identity is gated. */}
        <Reveal
          revealed={lotRevealed}
          concealed={
            <div aria-label="Revealing this lot's player" className="flex min-h-64 w-full flex-col items-center justify-center gap-2">
              <LotSpinner lot={lot} lots={lots} currentLot={turn.currentLot} />
              <span className="font-mono text-xs font-bold tracking-[0.15em] text-panel uppercase">Revealing…</span>
            </div>
          }
        >
          <div className="flex w-full flex-col items-center">
            <LotPortrait name={lot.display_name} headshotUrl={lot.headshot_url} className="h-28 w-28 text-4xl" />
            <h2 className="mt-3 max-w-full truncate font-slab text-3xl leading-none uppercase text-fg">{lot.display_name}</h2>
            <AuctionMatchup lot={lot} />
          </div>
        </Reveal>
        {phase === "sold" ? <div className="mt-4 w-full"><SoldHeadline lot={lot} players={players} /></div> : null}
        {/* The score is the card's final band: it stays concealed during the
            contest, then turns into a bold result without becoming a second,
            disconnected card. */}
        <div className="mt-4 -mx-4 -mb-5 w-[calc(100%+2rem)] border-t border-line">
          <Reveal
            revealed={phase === "sold"}
            concealed={
              <Concealed label="Fantasy points, hidden until this lot is won" className="rounded-none px-3.5 py-4">
                <div className="relative flex flex-col items-center gap-1 text-center">
                  <span className="font-mono text-xs font-bold tracking-[0.15em] text-panel uppercase">Fantasy points</span>
                  <span className="font-slab text-4xl leading-none text-panel">? ? ?</span>
                  {/* This player's own scouted tier only -- the row behind it
                      never reaches a client it doesn't belong to (0159), so
                      there's no cross-viewer leak to guard against here. The
                      control that produces this now lives in the token tray
                      below the clock, alongside Pass and Seal. */}
                  {myHint ? (
                    <span role="img" aria-label={`Scouted: a ${myHint.tier} performance`} className="type-label font-bold text-panel-muted">
                      Scouted: {myHint.tier}
                    </span>
                  ) : null}
                </div>
              </Concealed>
            }
          >
            <PointsReveal lot={lot} tier={revealTier} />
          </Reveal>
        </div>
      </div>

      {/* Mounted for the whole lot rather than created with the reveal. A
          status region that enters the DOM already holding its text is
          announced inconsistently — the region has to exist first and then
          change, which is what the countdown's live region does too. */}
      <p role="status" className="sr-only">
        {phase === "sold"
          ? lot.winner_id
            ? `${lot.display_name} sold to ${players.find((player) => player.user_id === lot.winner_id)?.display_name ?? "the winning player"} for $${lot.price ?? 0}. It reveals ${fmt(lot.points)} fantasy points.`
            : `${lot.display_name} received no bids.`
          : ""}
      </p>

      </section>

      <section className="flex min-h-0 flex-col gap-3 lg:col-start-1 lg:row-start-1" aria-label="The controls">
        {me ? (
          <>
            {phase === "sealed" ? (
              <SealedBidBar
                budget={me.budget}
                pending={pending}
                paused={isPaused}
                error={error}
                mine={mySeal}
                waitingOn={players
                  .filter((p) => p.user_id !== me.user_id && eligibleFor(lot, lots, players, p.user_id, format))
                  .filter((p) => !hasSubmittedSealedBid(sealedStatuses, lot.seq, p.user_id))
                  .map((p) => p.display_name)}
                onSubmit={submitSealedBid}
              />
            ) : (
              <BidBar
                phase={phase}
                price={price}
                budget={me.budget}
                onClock={onClock}
                isMine={phase === "bidding_self"}
                blocked={blocked}
                pending={pending}
                paused={isPaused}
                error={error}
                position={lot.position}
                targetSlot={targetSlotFor(lot, filled, format)}
                freeFallback={turn.freeFallbackSeat != null && price === 0}
                stuck={stuck}
                passTokenAvailable={passTokenAvailable}
                onRaise={(amount) => act(getClient().schema("auction").rpc("place_bid", { p_match_id: matchId, p_amount: amount }))}
                onPass={passLot}
              />
            )}
            <AuctionClock phase={phase} remainingMs={remainingMs} onClock={onClock} isMine={phase === "bidding_self"} />
            {format && format.tokenCount > 0 ? (
              <TokenTray
                remaining={tokensRemaining(format, me)}
                total={format.tokenCount}
                tokens={[
                  {
                    key: "pass",
                    label: "Pass",
                    description: "Decline a lot you'd otherwise be stuck with, for free. Usable only when you're the only bidder left on it.",
                    icon: <PassTokenIcon className="h-5 w-5" />,
                    state: passState,
                    onUse: passState === "usable" ? passLot : undefined,
                    pending,
                  },
                  {
                    key: "scout",
                    label: "Scout",
                    description: "Peek a rough performance tier for the current lot before it sells. Only you see it; on a season-total match it compares the lot against that position across every season.",
                    icon: <ScoutTokenIcon className="h-5 w-5" />,
                    state: scoutState,
                    onUse: scoutState === "usable" ? scoutLot : undefined,
                    pending: scoutPending,
                  },
                  {
                    key: "seal",
                    label: "Seal",
                    description: "Force this lot into a simultaneous blind bid instead of back-and-forth raising.",
                    icon: <SealTokenIcon className="h-5 w-5" />,
                    state: sealState,
                    onUse: sealState === "usable" ? sealLot : undefined,
                    pending,
                  },
                ]}
              />
            ) : null}
            {scoutError ? <p role="alert" className="text-xs text-hidden-text">{scoutError}</p> : null}
          </>
        ) : <p className="min-h-17 text-sm text-fg-muted">You&apos;re watching this one.</p>}
      </section>

      <aside className="min-h-0 overflow-y-auto lg:col-start-3 lg:row-start-1" aria-label="The table">
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
        price={price}
        sealed={phase === "sealed"}
        submittedSeats={phase === "sealed"
          ? players.filter((p) => hasSubmittedSealedBid(sealedStatuses, lot.seq, p.user_id)).map((p) => p.seat)
          : []}
      />
      </aside></div>
    </PageShell>
  );
}

/**
 * A token's state in the tray below the clock: usable right now, used up
 * for the rest of the match, or simply not applicable to this moment (a
 * budget of zero, a spent token, or a game state the ability doesn't reach
 * -- Pass outside a stuck turn, Scout once a lot is sold, Seal once a
 * bid already exists). All three stay visible either way, so the tray never
 * has to explain a control that's simply gone.
 */
type TokenState = "usable" | "inactive" | "used";

/** The shape auction_turn arrives in, from an RPC or from a replicated row. */
type AuctionTurnRow = {
  lot_count: number | null;
  current_lot: number | null;
  turn_seat: number | null;
  opener_seat: number | null;
  free_fallback_seat?: number | null;
  stuck_seat?: number | null;
  turn_deadline: string | null;
  phase?: string | null;
  phase_deadline?: string | null;
  server_now?: string | null;
};

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
  const current = useRef<HTMLLIElement>(null);
  // Whose turn it is, not just which lot is up — the same "who" a snake
  // board's own icon leads with, and public the moment a turn opens even
  // though the lot itself may still be unsold.
  const onClock = players.find((player) => player.seat === turn.turnSeat) ?? null;

  useEffect(() => {
    current.current?.scrollIntoView({
      behavior: "smooth",
      inline: "center",
      block: "nearest",
    });
  }, [turn.currentLot]);

  return (
    <MatchStrip ariaLabel="Auction board">
      {Array.from({ length: turn.lotCount }, (_, index) => {
        const seq = index + 1;
        if (seq === turn.currentLot) {
          return <CurrentBoardCell key={seq} ref={current} seq={seq} lotCount={turn.lotCount} phase={phase} onClock={onClock} />;
        }

        const settled = lots.find((candidate) => candidate.seq === seq) ?? null;
        return settled && seq < turn.currentLot ? (
          <SettledBoardCell key={seq} lot={settled} players={players} />
        ) : (
          <UndealtBoardCell key={seq} seq={seq} />
        );
      })}
    </MatchStrip>
  );
}

function SettledBoardCell({ lot, players }: { lot: Lot; players: Player[] }) {
  const winner = players.find((player) => player.user_id === lot.winner_id) ?? null;
  const price = lot.price === null ? "no price" : `$${lot.price}`;
  const winnerCopy = winner ? `won by ${winner.display_name}` : "no winner";

  return (
    <StripCell tone="settled" width={92} ariaLabel={`Lot ${lot.seq}, ${lot.display_name}, ${lot.slot ?? "unfilled"}, ${price}, ${winnerCopy}`}>
      <StripCellTop left={lot.slot ?? "—"} right={lot.price === null ? "—" : `$${lot.price}`} />
      <StripCellMedia>{lot.headshot_url ? <img src={lot.headshot_url} alt="" className="h-full w-full object-cover object-top" /> : null}</StripCellMedia>
      <StripCellName center>{abbreviate(lot.display_name)}</StripCellName>
      <StripCellCaption center>{winner?.display_name ?? "No bids"}</StripCellCaption>
    </StripCell>
  );
}

function CurrentBoardCell({
  seq,
  lotCount,
  phase,
  onClock,
  ref,
}: {
  seq: number;
  lotCount: number;
  phase: ReturnType<typeof viewerPhase>;
  onClock: Player | null;
  ref?: Ref<HTMLLIElement>;
}) {
  return (
    <StripCell tone="current" width={176} ref={ref}>
      {onClock ? <StripCellAvatar name={onClock.display_name} big /> : null}
      <StripCellTextColumn>
        <StripCellTitle meta={`/ ${lotCount}`}>Lot {seq}</StripCellTitle>
        <StripCellCaption>{phase === "lot_preview" ? "Coming up" : phase === "sold" ? "Sold" : phase === "sealed" ? "Sealed bidding" : "On the clock"}</StripCellCaption>
        {onClock ? <StripCellCaption>{onClock.display_name}</StripCellCaption> : null}
      </StripCellTextColumn>
    </StripCell>
  );
}

function UndealtBoardCell({ seq }: { seq: number }) {
  return (
    <StripCell tone="upcoming" width={92} ariaLabel={`Lot ${seq}, not yet dealt`} className="gap-2">
      <span aria-hidden className="mx-auto block h-7 w-7 rounded-full border border-dashed border-line" />
      <span className="text-center font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted tabular-nums">{seq}</span>
    </StripCell>
  );
}

function shuffle<T>(items: T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [copy[i], copy[j]] = [copy[j], copy[i]]; }
  return copy;
}

/**
 * The concealed side of the lot reveal: a slot-machine reel cycling through
 * decoy names and landing on the real player as <Reveal> swaps to the final
 * card. This deliberately follows Sabotage Draft's TurnSpinner: the answer
 * is the last physical reel row, not a separate card that appears after the
 * reel has stopped.
 *
 * Decoys come only from already-settled lots (`seq < currentLot`) -- the
 * same lots SettledBoardCell already names in the board strip above. Later,
 * undealt lots stay unnamed everywhere else in this UI (UndealtBoardCell
 * shows no identity), so the reel doesn't spoil those either, even though
 * their rows are technically already sitting in `lots`.
 */
function LotSpinner({ lot, lots, currentLot }: { lot: Lot; lots: Lot[]; currentLot: number }) {
  // Snapshot at mount, not live: `lots` gets a fresh array reference on every
  // realtime refetch (see refetch()'s unconditional setLots), most of them
  // unrelated to this lot. Re-deriving decoys off a moving `lots` would
  // reshuffle the reel mid-spin; a snapshot from the moment this reveal
  // started can't.
  const decoys = useMemo(() => {
    const settled = shuffle(lots.filter((candidate) => candidate.seq < currentLot)).slice(0, 7);

    // The first lot has no earlier player to borrow, and the second has only
    // one. Repeat a neutral reel row instead of borrowing future lots: that
    // would spoil players before their own reveal. Seven rows keeps the
    // travel distance stable; `lot` is always appended below as the answer.
    return Array.from({ length: 7 }, (_, index) => settled[index] ?? null);
  // This is intentionally a snapshot for one spin; realtime refreshes must
  // not reshuffle its rows mid-animation.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lot.seq]);
  const reelItems = [...decoys, lot];

  return (
    <SlotReel
      items={reelItems}
      durationMs={LOT_REVEAL_MS}
      reelKey={lot.seq}
      viewportClassName="h-52 w-full"
      rowClassName="h-52 flex-col items-center justify-center gap-2"
      itemKey={(item, index) => item ? `${item.seq}-${index}` : `placeholder-${index}`}
      renderItem={(item) => (
        <>
          {item ? (
            <>
              <LotPortrait name={item.display_name} headshotUrl={item.headshot_url} className="h-20 w-20 text-2xl" />
              <span className="max-w-[85%] truncate font-slab text-lg tracking-[0.02em] text-panel uppercase">{item.display_name}</span>
            </>
          ) : (
            <>
              <span aria-hidden className="flex h-20 w-20 items-center justify-center rounded-full border border-dashed border-panel-muted font-slab text-4xl text-panel-muted">?</span>
              <span className="font-mono text-xs tracking-[0.15em] text-panel-muted uppercase">Scanning…</span>
            </>
          )}
        </>
      )}
    />
  );
}

function LotPortrait({ name, headshotUrl, className = "h-16 w-16 text-2xl" }: { name: string; headshotUrl: string | null; className?: string }) {
  const [failed, setFailed] = useState(false);
  if (headshotUrl && !failed) {
    return <img src={headshotUrl} alt="" onError={() => setFailed(true)} className={`shrink-0 rounded-full bg-panel-shade object-cover object-top ${className}`} />;
  }
  return <span aria-hidden className={`flex shrink-0 items-center justify-center rounded-full bg-hidden font-slab text-panel ${className}`}><span className="font-slab-optical-center">{name.slice(0, 1).toUpperCase()}</span></span>;
}

function AuctionTeam({ code }: { code: string }) {
  const logoCode = auctionLogoCode(code);
  return (
    <span className="flex min-w-0 flex-1 flex-col items-center gap-1.5">
      {logoCode ? <TeamLogo code={logoCode} className="h-9 w-9" /> : <span aria-hidden className="h-9 w-9 rounded-full border border-line" />}
      <span className="font-slab text-lg leading-none text-fg uppercase">{code}</span>
    </span>
  );
}

function AuctionMatchup({ lot }: { lot: Lot }) {
  const weekly = lot.week !== null && lot.opponent !== null;
  return (
    <div className="mt-4 w-full border-t border-line pt-3" aria-label={weekly ? `${lot.season}, week ${lot.week}, ${lot.team} versus ${lot.opponent}` : `${lot.season} season, ${lot.team}`}>
      <p className="type-label text-fg-muted">{weekly ? `${lot.season} · week ${lot.week}` : `${lot.season} season`}</p>
      {weekly ? (
        <div className="mt-2 flex items-center gap-3">
          <AuctionTeam code={lot.team} />
          <span className="type-label text-fg-muted">vs</span>
          <AuctionTeam code={lot.opponent!} />
        </div>
      ) : <div className="mt-2 flex justify-center"><AuctionTeam code={lot.team} /></div>}
    </div>
  );
}

/**
 * The payoff is the concealed surface turning over, not a second card. The
 * visible face stays out of the accessibility tree entirely: the lot's status
 * region gives screen-reader users one complete, ordered announcement instead.
 */
function SoldHeadline({ lot, players }: { lot: Lot; players: Player[] }) {
  const winner = players.find((player) => player.user_id === lot.winner_id) ?? null;

  if (!lot.winner_id) {
    return (
      <p className="bg-surface-raised px-3.5 py-2 type-label-lg text-fg-muted shadow-well">
        No sale
      </p>
    );
  }

  return (
    <div aria-hidden className="animate-sold-headline border border-panel bg-panel px-3.5 py-2.5 text-panel-fg shadow-card">
      <p className="type-label text-panel-muted">Sold to</p>
      <p className="mt-1 flex items-baseline justify-between gap-3 font-slab text-xl leading-none uppercase">
        <span className="truncate">{winner?.display_name ?? "Unknown buyer"}</span>
        <span className="shrink-0 font-mono text-sm tabular-nums">${lot.price ?? 0}</span>
      </p>
    </div>
  );
}

function PointsReveal({ lot, tier }: { lot: Lot; tier: ReturnType<typeof weeklyRevealTier> }) {
  const copy = tier === "rough" ? "Rough outing" : tier === "solid" ? "Solid game" : tier === "great" ? "Big game" : null;
  return (
    <div aria-hidden className={`auction-points-reveal auction-points-reveal--${tier ?? "season"} flex flex-col items-center gap-1 bg-panel px-3.5 py-4 text-center text-panel-fg`}>
      <span className="font-mono text-xs font-bold tracking-[0.15em] text-panel-muted uppercase">
        Fantasy points
      </span>
      <span className={`min-w-0 font-slab text-4xl leading-none tabular-nums ${tier === "rough" ? "text-grade-rough" : tier === "solid" ? "text-grade-strong" : tier === "great" ? "text-grade-elite" : ""}`}>
        {fmt(lot.points)}
      </span>
      {copy ? <span className="type-label font-bold text-panel-muted">{copy}</span> : null}
    </div>
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
  price,
  sealed = false,
  submittedSeats = [],
}: {
  players: Player[];
  lots: Lot[];
  viewerId: string;
  turnSeat: number | null;
  holder: string | null;
  passedSeats: number[];
  soldLot: Lot | null;
  format: AuctionFormat | null;
  price: number;
  /** True during a sealed round -- there's no single acting seat to show,
   *  just who's locked in (0160). */
  sealed?: boolean;
  submittedSeats?: number[];
}) {
  return (
    <div className="auction-roster-board mt-2 flex flex-col divide-y divide-line border border-line bg-surface-raised">
      {players.map((player) => {
        const acting = player.seat === turnSeat;
        const total = revealedTotal(lots, player.user_id);
        const holding = holder === player.user_id;
        const mine = player.user_id === viewerId;
        const highlightLot = soldLot?.winner_id === player.user_id ? soldLot : null;
        const filled = lots.filter((lot) => lot.winner_id === player.user_id && lot.slot !== null).length;
        const slotCount = rosterSlots(format).length;
        const status = sealed
          ? (submittedSeats.includes(player.seat) ? "Submitted" : "Deciding")
          : holding
          ? `High bid · $${price}`
            : acting
              ? "On the clock"
              : passedSeats.includes(player.seat)
                ? "Passed"
                : `${filled}/${slotCount} filled`;

        return (
          <details
            key={player.user_id}
            open={mine}
            className={`transition-colors ${
              soldLot?.winner_id === player.user_id
                ? "bg-panel/10 motion-safe:animate-sold-once"
                : holding
                  ? "bg-panel/5"
                  : acting
                    ? "bg-panel/5"
                    : "bg-transparent"
            }`}
          >
            <summary className="grid cursor-pointer grid-cols-[1.85rem_minmax(0,1fr)_auto_1rem] items-center gap-2.5 px-3 py-2.5 hover:bg-panel/5">
              <AuctionRosterAvatar name={player.display_name} avatarUrl={player.avatar_url} mine={mine} />
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="flex min-w-0 items-center gap-1.5 font-slab text-base leading-none uppercase">
                  <span className="truncate">{mine ? "You" : player.display_name}</span>
                  {mine ? <span className="font-mono text-[8px] tracking-[0.07em] text-hidden-text">YOU</span> : null}
                </span>
                <span className={`font-mono text-[9px] tracking-[0.07em] uppercase ${acting || holding ? "text-hidden-text" : "text-fg-muted"}`}>
                  {status}
                </span>
              </span>
              <span className="flex items-center gap-2 whitespace-nowrap font-mono text-[11px] tabular-nums">
                <span className="text-fg-muted">${player.budget}</span>
                {format && format.tokenCount > 0 ? (
                  <span
                    role="img"
                    aria-label={`${tokensRemaining(format, player)} of ${format.tokenCount} tokens left`}
                    className="text-fg-muted"
                    title="Tokens left"
                  >
                    🎫{tokensRemaining(format, player)}
                  </span>
                ) : null}
                <span role="img" aria-label={`${fmt(total)} points`} className="text-lg font-bold leading-none text-fg">{fmt(total)}</span>
              </span>
              <Chevron className="roster-chev h-4 w-4 shrink-0 text-fg-muted transition-transform" />
            </summary>
            <div className="px-2.5 pb-2.5">
              <div className="flex flex-col gap-1.5 bg-panel p-1.5 text-panel-fg">
                <Roster lots={lots} userId={player.user_id} format={format} highlightLot={highlightLot} />
              </div>
            </div>
          </details>
        );
      })}
    </div>
  );
}

function AuctionRosterAvatar({ name, avatarUrl, mine }: { name: string; avatarUrl: string | null; mine: boolean }) {
  const [failed, setFailed] = useState(false);
  if (avatarUrl && !failed) return <img src={avatarUrl} alt="" onError={() => setFailed(true)} className="h-7 w-7 shrink-0 rounded-full object-cover" />;
  return <span aria-hidden className={`flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-full ${mine ? "ring-2 ring-hidden" : ""}`}><GeneratedAvatar name={name} size={28} className="h-full w-full" /></span>;
}

function Chevron({ className }: { className?: string }) {
  return <svg aria-hidden viewBox="0 0 16 16" fill="none" className={className}><path d="m6 3 5 5-5 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}

/** Filled slots are a legible roster row; empty slots remain a dashed gap. */
function Roster({ lots, userId, format, highlightLot = null }: { lots: Lot[]; userId: string; format: AuctionFormat | null; highlightLot?: Lot | null }) {
  const slots = rosterSlots(format);
  const wonBySlot = (slot: Slot) => lots.filter((lot) => lot.winner_id === userId && lot.slot === slot);
  return (
    <div className="flex flex-col gap-1.5">
      {slots.map(({ slot, index, label }) => {
        const won = wonBySlot(slot)[index - 1] ?? null;
        const justAdded = won?.seq === highlightLot?.seq;
        const tone = won ? "border-panel-fg/10 bg-panel-fg/[0.02]" : "border-dashed border-panel-fg/10";

        return (
          <div key={`${slot}-${index}`} className={`flex min-h-10 items-center justify-between gap-3 rounded border px-2.5 py-2 ${tone} ${justAdded ? "ring-2 ring-panel motion-safe:animate-player-to-roster" : ""}`}>
            <span className="shrink-0 type-label text-panel-muted">{label}</span>
            {won ? (
              <span role="img" aria-label={`${label} slot, ${won.display_name}, ${fmt(won.points)} points`} className="flex min-w-0 items-center gap-2 text-sm">
                {won.headshot_url ? <img src={won.headshot_url} alt="" className="h-6 w-6 shrink-0 rounded-full bg-panel-shade object-cover object-top" /> : <span aria-hidden className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-hidden font-slab text-[9px] text-panel">{won.display_name.slice(0, 1)}</span>}
                <span className="truncate font-semibold">{won.display_name}</span>
                <span className="shrink-0 font-mono text-[11px] tabular-nums text-panel-muted">{fmt(won.points)}</span>
              </span>
            ) : <span role="img" aria-label={`${label} slot, empty`} className="font-mono text-[10px] text-panel-muted">— empty —</span>}
          </div>
        );
      })}
    </div>
  );
}

/**
 * The controls. Their own column now, so they sit at the top of it beside the
 * card rather than hanging off the bottom of the window — the countdown is the
 * thing a player reads under pressure and it belongs at eye level. Still on
 * --surface-raised, which the token file annotates as where a bid bar goes.
 *
 * A disabled control always says why. Four different situations produce the
 * same greyed button otherwise, and "you already have a quarterback" being
 * indistinguishable from a broken app is the difference between a rule and a
 * bug.
 */
function AuctionClock({ phase, remainingMs, onClock, isMine }: { phase: AuctionPhase; remainingMs: number | null; onClock: Player | null; isMine: boolean }) {
  const seconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);
  const live = phase === "bidding_self" || phase === "bidding_other" || phase === "sealed";
  const duration = phase === "sealed" ? DURATION_MS.sealed : live ? DURATION_MS.bidding : DURATION_MS[phase === "sold" ? "sold" : "lot_preview"];
  const fraction = remainingMs === null ? 0 : Math.min(1, remainingMs / (live ? duration - VISIBLE_SLACK_MS : duration));
  const urgent = remainingMs !== null && remainingMs <= 3_000 && live;
  const display = remainingMs === null ? "—" : remainingMs < TENTHS_THRESHOLD_MS ? (remainingMs / 1000).toFixed(1) : `${seconds}`;
  const announcement = live && seconds !== null && [10, 5, 3].includes(seconds) ? `${seconds} seconds left` : "";
  const tone = urgent ? "border-hidden bg-hidden/10 text-hidden-text" : "border-line bg-surface-raised text-fg";
  const label = phase === "lot_preview" ? "Bidding has not started"
    : phase === "sold" ? "Sold"
    : phase === "sealed" ? "Sealed bidding — everyone decides at once"
    : isMine ? "Your turn" : `${onClock?.display_name ?? "Someone"} is deciding`;

  return (
    <section aria-label="Clock" className={`border p-3 transition-colors ${tone}`}>
      <p className="type-label-lg text-fg-muted">{label}</p>
      <p className={`mt-1 font-mono text-5xl leading-none tabular-nums ${urgent ? "text-hidden-text" : ""}`} aria-hidden>{display}</p>
      <p aria-live="polite" className="sr-only">{announcement}</p>
      <div role="timer" aria-label={seconds === null ? "No timer" : `${seconds} seconds left`} className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-current/20">
        <div className="h-full bg-current" style={{ width: `${fraction * 100}%`, transition: `width ${TICK_MS}ms linear` }} />
      </div>
    </section>
  );
}

/**
 * The three single-use abilities, always shown together below the clock once
 * tokens are on for this match (0158/0159/0160) -- a token never disappears
 * from the tray, it only changes state, so a player always knows all three
 * exist even on a match where they've spent two of them already.
 */
type TokenDef = { key: string; label: string; description: string; icon: ReactNode; state: TokenState; onUse?: () => void; pending?: boolean };

function TokenTray({ remaining, total, tokens }: { remaining: number; total: number; tokens: TokenDef[] }) {
  // One shared tooltip, left-aligned to the tray, rather than one per
  // button -- the leftmost token's own popover would otherwise render off
  // the left edge of the screen. Which token's copy it shows is just local
  // hover/focus state; the description text itself still lives on each
  // button (sr-only) so a screen reader announces it without this state at
  // all.
  const [activeKey, setActiveKey] = useState<string | null>(null);
  const active = tokens.find((token) => token.key === activeKey) ?? null;

  return (
    // Mirrors AuctionClock's own section/label pairing just above it, so the
    // two controls under the clock read as a matched set rather than one
    // titled area and one unlabeled row of icons.
    <section aria-label={`Tokens, ${remaining} of ${total} left`}>
      <p aria-hidden className="type-label-lg text-fg-muted">
        Tokens · {remaining} of {total} left
      </p>
      <div className="relative mt-2 flex items-center gap-2.5">
        {tokens.map(({ key, ...token }) => (
          <TokenButton
            key={key}
            tokenKey={key}
            {...token}
            onHoverChange={(hovering) => setActiveKey((current) => (hovering ? key : current === key ? null : current))}
          />
        ))}
        {active ? (
          <div
            role="tooltip"
            className="pointer-events-none absolute top-full left-0 z-20 mt-1.5 w-48 bg-panel px-2.5 py-2 text-left font-sans text-[11px] leading-snug font-normal normal-case tracking-normal text-panel-fg shadow-card"
          >
            <span className="block type-label-xs font-bold text-panel-muted">{active.label} · {TOKEN_STATE_TEXT[active.state]}</span>
            {active.description}
          </div>
        ) : null}
      </div>
    </section>
  );
}

const TOKEN_STATE_TEXT: Record<TokenState, string> = {
  usable: "Ready to use.",
  used: "Already used this match.",
  inactive: "Not usable right now.",
};

const TOKEN_TONE: Record<TokenState, string> = {
  usable: "border-panel bg-panel text-panel-fg shadow-card",
  used: "border-line bg-surface text-fg-muted/35",
  inactive: "border-line bg-surface text-fg-muted/70",
};

function TokenButton({
  tokenKey,
  label,
  description,
  icon,
  state,
  onUse,
  pending,
  onHoverChange,
}: {
  tokenKey: string;
  label: string;
  description: string;
  icon: ReactNode;
  state: TokenState;
  onUse?: () => void;
  pending?: boolean;
  onHoverChange: (hovering: boolean) => void;
}) {
  const usable = state === "usable";
  const describedBy = `token-${tokenKey}-description`;

  return (
    // The hover handlers live on this wrapper, not the button: a disabled
    // button doesn't fire mouseenter/mouseleave in Chrome or Firefox (the
    // browser treats a disabled form control as non-interactive for pointer
    // events), which is why hovering an inactive or used token previously
    // showed nothing. A plain div has no such restriction.
    <div className="relative" onMouseEnter={() => onHoverChange(true)} onMouseLeave={() => onHoverChange(false)}>
      <button
        type="button"
        onClick={onUse}
        disabled={!usable || !!pending}
        aria-label={`${label} token`}
        aria-describedby={describedBy}
        onFocus={() => onHoverChange(true)}
        onBlur={() => onHoverChange(false)}
        className={`relative flex h-11 w-11 shrink-0 items-center justify-center rounded-full border transition-colors disabled:cursor-default ${TOKEN_TONE[state]}`}
      >
        {icon}
        {state === "used" ? (
          <span aria-hidden className="absolute -top-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-surface-raised text-[9px] leading-none text-fg-muted ring-1 ring-line">✓</span>
        ) : null}
        <span id={describedBy} className="sr-only">
          {label} · {TOKEN_STATE_TEXT[state]}. {description}
        </span>
      </button>
    </div>
  );
}

function PassTokenIcon({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="none" className={className}>
      <circle cx="8" cy="8" r="6" stroke="currentColor" strokeWidth="1.5" />
      <path d="M4.2 4.2 11.8 11.8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function ScoutTokenIcon({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="none" className={className}>
      <circle cx="6.75" cy="6.75" r="4" stroke="currentColor" strokeWidth="1.5" />
      <path d="M9.75 9.75 13 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function SealTokenIcon({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="none" className={className}>
      <rect x="3.5" y="7" width="9" height="6" rx="1.1" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/**
 * The sealed phase's own control: unlike BidBar, there is no turn to wait
 * for -- every live player sees this at once. Before submitting, a single
 * exact-amount field (first price, same mental model as BidBar's own
 * "Custom" input, just not an increment off a standing price that does not
 * exist here). After submitting, nothing left to decide -- just who the
 * engine is still waiting on, by name, never by amount (0160).
 */
function SealedBidBar({
  budget,
  pending,
  paused,
  error,
  mine,
  waitingOn,
  onSubmit,
}: {
  budget: number;
  pending: boolean;
  paused: boolean;
  error: string | null;
  /** The viewer's own submission, once made -- RLS means this can only ever be their own. */
  mine: SealedBid | null;
  /** Display names of live players who haven't submitted yet. */
  waitingOn: string[];
  onSubmit: (amount: number) => void;
}) {
  const [amount, setAmount] = useState("0");
  const invalid = !Number.isInteger(Number(amount)) || Number(amount) < 0 || Number(amount) > budget;

  return (
    <section aria-label="Sealed bid" className="border border-line bg-surface px-3 py-3">
      <p className="type-label-lg text-fg-muted">Sealed bid</p>
      <p className="mt-1 font-mono text-[11px] text-fg-muted tabular-nums">Your budget · ${budget} left</p>
      {mine ? (
        <div className="mt-3">
          <p className="font-slab text-2xl leading-none tabular-nums">You bid ${mine.amount}</p>
          <p className="mt-2 text-xs text-fg-muted">
            {waitingOn.length === 0
              ? "Everyone's in -- resolving…"
              : `Waiting on ${waitingOn.join(", ")}.`}
          </p>
        </div>
      ) : (
        <form
          className="mt-3 flex items-end gap-2"
          onSubmit={(event) => { event.preventDefault(); if (!invalid) onSubmit(Number(amount)); }}
        >
          <label className="flex-1 type-label-lg text-fg-muted">
            Amount
            <input
              value={amount}
              onChange={(event) => setAmount(event.target.value)}
              type="number"
              min={0}
              max={budget}
              step="1"
              inputMode="numeric"
              disabled={pending || paused}
              className="mt-1 block w-full border border-line bg-surface-raised px-2 py-2 font-mono text-lg font-bold"
            />
          </label>
          <Button type="submit" disabled={invalid || pending || paused} fullWidth={false}>Submit</Button>
        </form>
      )}
      <p role={error ? "alert" : undefined} className="mt-3 min-h-5 text-xs leading-5 text-fg-muted">
        {error ?? (mine ? "" : "Nobody sees this but you until the lot resolves.")}
      </p>
    </section>
  );
}

function BidBar({
  phase,
  price,
  budget,
  onClock,
  isMine,
  blocked,
  pending,
  paused,
  error,
  position,
  targetSlot,
  onRaise,
  onPass,
  freeFallback,
  stuck,
  passTokenAvailable,
}: {
  price: number;
  budget: number;
  onClock: Player | null;
  isMine: boolean;
  blocked: ReturnType<typeof blockedReason>;
  pending: boolean;
  paused: boolean;
  onRaise: (amount: number) => void;
  onPass: () => void;
  freeFallback: boolean;
  /** Nobody else is live on this lot -- the board would hand it to the
   * viewer for $0 the moment they act. Take it free, or spend a pass token
   * to let it go unsold instead. See migration 0158. */
  stuck: boolean;
  /** Whether the viewer still has an unspent pass token to decline with. */
  passTokenAvailable: boolean;
  phase: "lot_preview" | "bidding_self" | "bidding_other" | "sold";
  error: string | null;
  /** The lot's own position — what "full" refers to when it's fully blocked. */
  position: string;
  /** Where a win actually lands: natural slot if open, otherwise FLEX. */
  targetSlot: string;
}) {
  const [customFor, setCustomFor] = useState<string | null>(null);
  const [amount, setAmount] = useState(String(price + 1));
  const input = useRef<HTMLInputElement>(null);
  const customButton = useRef<HTMLButtonElement>(null);
  const surface = useRef<HTMLDivElement>(null);
  const claimable = freeFallback || stuck;
  const minimum = claimable ? 0 : price + 1;
  // Keying the popover to the interaction rather than to a boolean is what
  // closes it on a turn change, a new price or a sale: the key it was opened
  // against simply stops being the current one.
  const interactionKey = `${phase}:${onClock?.seat ?? "none"}:${price}`;
  const custom = customFor === interactionKey;
  const actionable = phase === "bidding_self" && blocked === null && !pending && !paused;

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
  const invalid = !Number.isInteger(Number(amount)) || Number(amount) < minimum || Number(amount) > budget;
  const status = paused
    ? "The host paused the game."
    : phase === "lot_preview"
    ? "This player enters the auction."
    : phase === "sold"
      ? "The next player is coming up."
      : blocked
        ? blocked === "no_slot"
          ? `Your ${position} slots are full.`
          : BLOCKED_TEXT[blocked]
        : stuck
          ? passTokenAvailable
            ? "Nobody else can bid on this one. Take it free, or spend your Pass token below to let it go unsold."
            : "Nobody else can bid on this one, and you're out of pass tokens — it's yours for $0."
        : freeFallback
          ? "Take this lot free, or pass it back to the original opener."
        : !canAfford(price, budget, INCREMENTS[1])
          ? `You can only raise by $${INCREMENTS[0]}.`
          : `A win fills your open ${targetSlot}.`;

  return (
    <section
      ref={surface}
      tabIndex={-1}
      aria-label="Bid controls"
      className="relative border border-line bg-surface px-3 py-3 outline-none"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="type-label-lg text-fg-muted">Standing bid</span>
        <span className="font-slab text-2xl leading-none tabular-nums">{phase === "lot_preview" ? "—" : `$${price}`}</span>
      </div>
      <p className="mt-1 font-mono text-[11px] text-fg-muted tabular-nums">Your budget · ${budget} left</p>
      {claimable && actionable ? <div className="mt-3 flex gap-2"><Button type="button" onClick={() => onRaise(0)}>Take for $0</Button></div> : null}
      {!claimable ? <div className="mt-3 flex gap-2">
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
      </div> : null}
      <p role={error && !custom ? "alert" : undefined} className={`mt-3 min-h-5 text-xs leading-5 ${error && !custom ? "text-hidden-text" : "text-fg-muted"}`}>{custom ? status : error ?? status}</p>
      {/* Passing is permanent for this lot, so it needs a deliberate,
          thumb-sized target of its own. Ghost keeps Raise as the primary
          action while the divider prevents a hurried bid from becoming a
          pass. The button remains in place while disabled so the controls
          never shift during a turn change. Stuck is the one case with no
          free pass at all -- declining there spends the Pass token in the
          tray below instead, so there is nothing for this button to do. */}
      {!stuck ? (
        <div className="mt-3 border-t border-line pt-3">
          <Button type="button" variant="ghost" disabled={!actionable} onClick={onPass}>
            {freeFallback ? "Pass to opener" : "Pass"}
          </Button>
        </div>
      ) : null}
      <AnimatePresence>
        {custom && (
          <motion.form
            role="dialog"
            aria-label="Custom bid"
            variants={dropdown}
            initial="initial"
            animate="animate"
            exit="exit"
            style={{ transformOrigin: "bottom center" }}
            className="absolute right-3 bottom-3 left-3 rounded-card bg-panel p-3 text-panel-fg shadow-card"
            onSubmit={(event) => { event.preventDefault(); if (!invalid) onRaise(Number(amount)); }}
            onKeyDown={(event) => { if (event.key === "Escape") { event.preventDefault(); closeCustom(); } }}
          >
            <label className="block type-label-lg text-panel-muted">Custom bid
              <input ref={input} value={amount} onChange={(event) => setAmount(event.target.value)} type="number" min={minimum} max={budget} step="1" inputMode="numeric" className="mt-2 block w-full border border-panel-muted bg-[#fffdf7] px-2 py-2 font-mono text-lg font-bold" />
            </label>
            <p className="mt-1 text-xs text-panel-muted">Minimum is ${minimum}. Your maximum is ${budget}.</p>
            {error ? <p role="alert" className="mt-1 text-xs text-hidden-ink">{error}</p> : null}
            <div className="mt-2 flex gap-2"><Button type="submit" variant="ink" fullWidth={false} disabled={invalid || pending}>Bid ${amount}</Button><button type="button" onClick={closeCustom} className="text-xs text-panel-muted underline">Cancel</button></div>
          </motion.form>
        )}
      </AnimatePresence>
    </section>
  );
}

/** Names a winner, so the game ends rather than merely stopping. */
function FinalScreen({
  lots,
  players,
  standings,
  viewerId,
  roomCode,
  matchId,
  isHost,
  format,
  era,
}: {
  lots: Lot[];
  players: Player[];
  standings: Standing[];
  viewerId: string;
  roomCode: string | null;
  matchId: string;
  isHost: boolean;
  format: AuctionFormat | null;
  era: { seasonMin: number; seasonMax: number; minSpan: number } | null;
}) {
  const ranked = byPlacement(standings);
  const nameOf = (userId: string) =>
    players.find((p) => p.user_id === userId)?.display_name ?? "Unknown player";
  const avatarOf = (userId: string) => players.find((p) => p.user_id === userId)?.avatar_url ?? null;
  const winners = ranked.filter((s) => s.placement === 1);
  const headline =
    winners.length === 0
      ? "Game over"
      : winners.length === 1
        ? `${nameOf(winners[0].user_id)} wins`
        : `${winners.map((w) => nameOf(w.user_id)).join(" & ")} tie`;

  const rows: FinalStandingsRow[] = ranked.map((standing) => ({
    userId: standing.user_id,
    rank: standing.placement ?? ranked.length,
    name: nameOf(standing.user_id),
    avatarUrl: avatarOf(standing.user_id),
    isViewer: standing.user_id === viewerId,
    statLine: `${fmt(standing.raw_score)} pts`,
    roster: <RosterFinal lots={lots} userId={standing.user_id} format={format} />,
  }));

  return (
    <>
      <FinalStandings headline={headline} rows={rows} />

      {roomCode ? <PostGameNavigation matchId={matchId} roomCode={roomCode} /> : null}
      {roomCode ? (
        <PostGameControls matchId={matchId} roomCode={roomCode} isHost={isHost} format={format} era={era} />
      ) : null}

      {!roomCode ? (
        <Link
          href="/"
          className="mt-2 text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
        >
          Back home
        </Link>
      ) : null}
    </>
  );
}

/** The auction's post-game roster, using the same portrait-forward rhythm as
 * Sabotage Draft's final roster while retaining price and fantasy points. */
function RosterFinal({ lots, userId, format }: { lots: Lot[]; userId: string; format: AuctionFormat | null }) {
  const won = lots.filter((l) => l.winner_id === userId);

  return (
    <dl className="flex flex-col gap-2">
      {rosterSlots(format).map(({ slot, index, label }) => {
        const lot = won.filter((l) => l.slot === slot)[index - 1] ?? null;
        const tier = lot ? weeklyRevealTier(lot) : null;
        return (
          <div key={`${slot}-${index}`} className="flex min-w-0 items-center gap-2.5">
            <dt className="w-9 shrink-0 type-label text-panel-muted">{label}</dt>
            {lot ? (
              <>
                <LotPortrait name={lot.display_name} headshotUrl={lot.headshot_url} className="h-7 w-7 text-xs" />
                <dd className="min-w-0 flex-1 truncate text-[11px] text-panel-fg">
                  <span className="font-semibold">{lot.display_name}</span>
                  <span className="ml-1 text-panel-muted">· {lot.season}</span>
                  <span className="ml-1 inline-flex items-center gap-1 text-panel-muted">
                    {auctionLogoCode(lot.team) ? <TeamLogo code={auctionLogoCode(lot.team)!} className="h-3 w-3" /> : null}
                    {lot.team}{lot.opponent ? ` vs ${lot.opponent}` : ""}
                  </span>
                </dd>
                <dd className="flex shrink-0 items-baseline gap-1.5 tabular-nums">
                  <span className="font-mono text-[10px] text-panel-muted">${lot.price}</span>
                  <span className={`font-slab text-lg leading-none ${tier === "rough" ? "text-grade-rough" : tier === "solid" ? "text-grade-strong" : tier === "great" ? "text-grade-elite" : "text-panel-fg"}`}>{fmt(lot.points)}</span>
                </dd>
              </>
            ) : <dd className="text-[11px] text-panel-muted">—</dd>}
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
