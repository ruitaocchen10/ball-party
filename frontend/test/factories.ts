import { vi } from "vitest";

import type { Bid, Lot, Player, Standing, Turn } from "@/lib/auction/board";

export const MATCH = "11111111-1111-1111-1111-111111111111";

/**
 * Seats are addressed by index everywhere below: SEATS[0] is the viewer in
 * every suite, so "my turn" and "somebody else's turn" are a single number.
 */
export const SEATS = [
  { user_id: "u0", display_name: "Ava", seat: 0 },
  { user_id: "u1", display_name: "Ben", seat: 1 },
  { user_id: "u2", display_name: "Cleo", seat: 2 },
  { user_id: "u3", display_name: "Dev", seat: 3 },
];

export function players(over: Partial<Player>[] = []): Player[] {
  return SEATS.map((seat, i) => ({
    match_id: MATCH,
    user_id: seat.user_id,
    seat: seat.seat,
    budget: 20,
    display_name: seat.display_name,
    ...over[i],
  }));
}

export function lot(over: Partial<Lot> = {}): Lot {
  return {
    match_id: MATCH,
    seq: 1,
    player_id: "00-0000001",
    display_name: "Saquon Barkley",
    position: "RB",
    season: 2018,
    week: 12,
    team: "NYG",
    opponent: "CHI",
    is_flex: false,
    headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/abc",
    winner_id: null,
    price: null,
    slot: null,
    points: null,
    resolved_at: null,
    ...over,
  };
}

/** A full board, so `chancesLeft` and the roster have something real to read. */
export function board(over: Partial<Lot>[] = []): Lot[] {
  const cards = [
    ["RB", "Saquon Barkley"],
    ["QB", "Patrick Mahomes"],
    ["WR", "Justin Jefferson"],
    ["TE", "Travis Kelce"],
  ];
  return cards.map(([position, display_name], i) =>
    lot({ seq: i + 1, position, display_name, ...over[i] }),
  );
}

export function bid(over: Partial<Bid> = {}): Bid {
  return {
    match_id: MATCH,
    seq: 1,
    bid_seq: 1,
    user_id: "u0",
    action: "raise",
    price: 5,
    by_timeout: false,
    created_at: new Date().toISOString(),
    ...over,
  };
}

export function standing(over: Partial<Standing> = {}): Standing {
  return {
    match_id: MATCH,
    run_id: "r1",
    user_id: "u0",
    placement: 1,
    points_awarded: null,
    raw_score: 100,
    team: null,
    ...over,
  };
}

/**
 * A turn in one of the four shared phases. `deadlineMs` is how far the live
 * clock is from running out, which is what the countdown assertions turn on.
 */
export function turn(
  phase: Turn["phase"],
  over: Partial<Turn> & { deadlineMs?: number } = {},
): Turn {
  const { deadlineMs = 10_000, ...rest } = over;
  const at = new Date(Date.now() + deadlineMs).toISOString();
  return {
    lotCount: 4,
    currentLot: 1,
    turnSeat: phase === "bidding" ? 0 : null,
    openerSeat: 0,
    turnDeadline: phase === "bidding" ? at : null,
    phase,
    phaseDeadline: phase === "bidding" ? null : at,
    ...rest,
  };
}

/**
 * The supabase client the component reaches for. Every RPC resolves to "no
 * change" by default; a suite that cares overrides `rpc` to reject or to hand
 * back a new turn.
 */
type RpcResult = { data: unknown; error: { message: string } | null };

/**
 * A chainable stand-in for a PostgREST query builder. Every terminal resolves
 * to no rows, which the component treats as "nothing to apply" — so the
 * reconciliation refetch runs without inventing state the suite did not set up.
 */
function query(table: string) {
  // The table is carried on the object so a failing assertion names it.
  const q: Record<string, unknown> = { table };
  for (const method of ["select", "eq", "order", "limit", "maybeSingle", "single"]) {
    q[method] = () => q;
  }
  q.then = (resolve: (value: { data: null; error: null }) => unknown) =>
    Promise.resolve({ data: null, error: null }).then(resolve);
  return q;
}

export function supabaseMock() {
  const rpc = vi.fn(async (): Promise<RpcResult> => ({ data: null, error: null }));
  const from = vi.fn((table: string) => query(table));
  const client = {
    rpc,
    from,
    channel: () => client,
    on: () => client,
    // The component passes a status callback; SUBSCRIBED triggers its refetch.
    subscribe: (onStatus?: (status: string) => void) => {
      onStatus?.("SUBSCRIBED");
      return client;
    },
    removeChannel: vi.fn(),
    realtime: { setAuth: vi.fn() },
    auth: { getSession: async () => ({ data: { session: null } }) },
  };
  return client;
}
