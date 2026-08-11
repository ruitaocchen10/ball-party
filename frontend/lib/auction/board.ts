import type { Database } from "@/lib/supabase/database.types";

/**
 * Everything the match screen needs to work out from the rows the server sent.
 *
 * All of it is derived rather than stored, and none of it is a rule: the
 * database decides every one of these questions again when a move arrives. The
 * point of computing them here is that a disabled button can say *why* — "you
 * already have a quarterback" and "it isn't your turn" are different sentences,
 * and one greyed button for both is the difference between a rule and a bug.
 */

export type Lot = Database["public"]["Tables"]["auction_lots"]["Row"];
export type Seat = Database["public"]["Tables"]["auction_players"]["Row"];
export type Bid = Database["public"]["Tables"]["auction_bids"]["Row"];
export type Standing = Database["public"]["Tables"]["match_players"]["Row"];

export type Player = Seat & { display_name: string };

/** The state of the board, as `auction_turn` hands it over. */
export type Turn = {
  lotCount: number;
  currentLot: number;
  turnSeat: number | null;
  openerSeat: number;
  turnDeadline: string | null;
  phase: "lot_preview" | "bidding" | "sold";
  phaseDeadline: string | null;
};

/** A dealt match's immutable format snapshot, loaded once beside the board. */
export type AuctionFormat = {
  scoringMode: string;
  rosterPreset: string;
  qbSlots: number;
  rbSlots: number;
  wrSlots: number;
  teSlots: number;
  flexSlots: number;
  purse: number;
};

export type AuctionPhase = "lot_preview" | "bidding_self" | "bidding_other" | "sold";

export function viewerPhase(turn: Turn, viewerSeat: number | null): AuctionPhase {
  if (turn.phase === "lot_preview" || turn.phase === "sold") return turn.phase;
  return turn.turnSeat === viewerSeat ? "bidding_self" : "bidding_other";
}

export const SLOTS = ["QB", "RB", "WR", "TE", "FLEX"] as const;
export type Slot = (typeof SLOTS)[number];

/** The two raises the rules allow. Anything else is refused, not clamped. */
export const INCREMENTS = [1, 5] as const;

export function lotAt(lots: Lot[], seq: number): Lot | null {
  return lots.find((lot) => lot.seq === seq) ?? null;
}

/** The opening price is $0, and an uncontested lot goes for it. */
export function standingPrice(bids: Bid[], seq: number): number {
  const raises = bids.filter((b) => b.seq === seq && b.action === "raise");
  return raises.length === 0 ? 0 : Math.max(...raises.map((b) => b.price ?? 0));
}

export function highBidder(bids: Bid[], seq: number): string | null {
  const raises = bids.filter((b) => b.seq === seq && b.action === "raise");
  if (raises.length === 0) return null;
  return raises.reduce((a, b) => (b.bid_seq > a.bid_seq ? b : a)).user_id;
}

export function hasPassed(bids: Bid[], seq: number, userId: string): boolean {
  return bids.some((b) => b.seq === seq && b.user_id === userId && b.action === "pass");
}

/** A player's roster is the slots on the lots they won — there is no roster table. */
export function filledSlots(lots: Lot[], userId: string): Set<string> {
  return new Set(
    lots.filter((lot) => lot.winner_id === userId && lot.slot !== null).map((lot) => lot.slot!),
  );
}

/**
 * A base lot may only be bid on by a player whose natural slot is still open;
 * FLEX is live during the flex round and nowhere else. That restriction is what
 * makes the board solvable — see the migration and the game doc.
 */
export function eligibleFor(lot: Lot, filled: Set<string>): boolean {
  return !filled.has(lot.is_flex ? "FLEX" : lot.position);
}

/** What a lot fills if you win it. Never ambiguous, which follows from the rule above. */
export function slotFor(lot: Lot): Slot {
  return (lot.is_flex ? "FLEX" : lot.position) as Slot;
}

/**
 * How many more shots at this slot are coming, this one included. The cheap
 * mitigation that gives a blind board's budget teeth: "is this my last chance
 * at a tight end" has to be knowable.
 */
export function chancesLeft(lots: Lot[], lot: Lot, currentLot: number): number {
  return lots.filter(
    (candidate) =>
      candidate.seq >= currentLot &&
      candidate.is_flex === lot.is_flex &&
      (lot.is_flex || candidate.position === lot.position),
  ).length;
}

export function revealedTotal(lots: Lot[], userId: string): number {
  return lots
    .filter((lot) => lot.winner_id === userId)
    .reduce((sum, lot) => sum + Number(lot.points ?? 0), 0);
}

/** Why the controls are off. Null means they are on. */
export type Blocked = "not_your_turn" | "no_slot" | "passed" | "cannot_afford";

export const BLOCKED_TEXT: Record<Blocked, string> = {
  not_your_turn: "Waiting on another player",
  no_slot: "You have no open slot for this position",
  passed: "You passed on this lot",
  cannot_afford: "You can't afford the next raise",
};

export function blockedReason(args: {
  lot: Lot;
  me: Player | null;
  turnSeat: number | null;
  filled: Set<string>;
  passed: boolean;
  price: number;
}): Blocked | null {
  const { lot, me, turnSeat, filled, passed, price } = args;
  if (!me) return "not_your_turn";
  if (!eligibleFor(lot, filled)) return "no_slot";
  if (passed) return "passed";
  if (turnSeat !== me.seat) return "not_your_turn";
  // Not a block on its own: a player with nothing left can still take an
  // uncontested lot for $0, so an empty wallet costs contested lots and never
  // costs slots. It only closes the raise buttons.
  if (price + Math.min(...INCREMENTS) > me.budget) return "cannot_afford";
  return null;
}

export function canAfford(price: number, budget: number, increment: number): boolean {
  return price + increment <= budget;
}

/** Weekly cards show their matchup; season cards show the stable player-season identity. */
export function matchupLine(lot: Lot): string {
  if (lot.week === null || lot.opponent === null) {
    return `${lot.position} · ${lot.season} · ${lot.team}`;
  }
  return `${lot.position} · ${lot.season} · Week ${lot.week} · vs ${lot.opponent}`;
}

export function byPlacement(standings: Standing[]): Standing[] {
  return [...standings].sort(
    (a, b) => (a.placement ?? 99) - (b.placement ?? 99) || Number(b.raw_score) - Number(a.raw_score),
  );
}
