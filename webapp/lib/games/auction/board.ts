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
/**
 * A scouted tier, RLS-scoped to its own owner (0159) — the rows this client
 * ever receives are only the viewer's own, never an opponent's, regardless
 * of how many players are in the match.
 */
export type ScoutHint = Database["public"]["Tables"]["auction_scouting_hints"]["Row"];
/**
 * A sealed-round bid amount, RLS-scoped to its own owner the same way
 * ScoutHint is (0160) — this client never receives an opponent's amount,
 * win or lose.
 */
export type SealedBid = Database["public"]["Tables"]["auction_sealed_bids"]["Row"];
/**
 * Presence, not value: readable by any match member, so "you've submitted /
 * waiting on Tasha" is renderable without the amount ever leaking (0160).
 */
export type SealedBidStatus = Database["public"]["Tables"]["auction_sealed_bid_statuses"]["Row"];

export type Player = Seat & { display_name: string; avatar_url: string | null };

/** The state of the board, as `auction_turn` hands it over. */
export type Turn = {
  lotCount: number;
  currentLot: number;
  turnSeat: number | null;
  openerSeat: number;
  freeFallbackSeat: number | null;
  /**
   * The seat the board is about to hand this lot to for free because nobody
   * else is live on it -- the same shape as `freeFallbackSeat`, but for "you
   * are the only eligible bidder" rather than "you are the broke opener".
   * That seat gets a real turn instead of an automatic $0 win: take it, or
   * spend a pass token to let it go unsold. See migration 0158.
   */
  stuckSeat: number | null;
  turnDeadline: string | null;
  phase: "lot_preview" | "bidding" | "sold" | "sealed";
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
  seasonFrom: number;
  seasonTo: number;
  /** How many of Pass/Scout/Seal a player may invoke this match, total. */
  tokenCount: number;
};

/** The era the board was dealt from, as the format line names it. */
export function eraLabel(format: AuctionFormat): string {
  return `${format.seasonFrom}-${format.seasonTo}`;
}

/**
 * "sealed" is its own case, not a self/other split -- unlike ascending
 * bidding, every live player acts in the same window, so there is no single
 * seat whose turn it is to distinguish (0160).
 */
export type AuctionPhase = "lot_preview" | "bidding_self" | "bidding_other" | "sold" | "sealed";

export function viewerPhase(turn: Turn, viewerSeat: number | null): AuctionPhase {
  if (turn.phase === "lot_preview" || turn.phase === "sold" || turn.phase === "sealed") return turn.phase;
  return turn.turnSeat === viewerSeat ? "bidding_self" : "bidding_other";
}

export const SLOTS = ["QB", "RB", "WR", "TE", "FLEX"] as const;
export type Slot = (typeof SLOTS)[number];

export type RosterSlot = { slot: Slot; index: number; label: string };

/** A match may predate roster formats; those boards retain the original shape. */
const STANDARD_LIMITS: Record<Slot, number> = { QB: 1, RB: 1, WR: 1, TE: 1, FLEX: 1 };

export function slotLimits(format: AuctionFormat | null): Record<Slot, number> {
  if (!format) return STANDARD_LIMITS;
  return { QB: format.qbSlots, RB: format.rbSlots, WR: format.wrSlots, TE: format.teSlots, FLEX: format.flexSlots };
}

/** Every visible roster position, including an independently readable repeat. */
export function rosterSlots(format: AuctionFormat | null): RosterSlot[] {
  const limits = slotLimits(format);
  return SLOTS.flatMap((slot) =>
    Array.from({ length: limits[slot] }, (_, index) => ({
      slot,
      index: index + 1,
      label: limits[slot] === 1 ? slot : `${slot} ${index + 1}`,
    })),
  );
}

/** The two raises the rules allow. Anything else is refused, not clamped. */
export const INCREMENTS = [1, 5] as const;

export function lotAt(lots: Lot[], seq: number): Lot | null {
  return lots.find((lot) => lot.seq === seq) ?? null;
}

/** Replaces the lot with the same seq, or appends it (a redrawn lot), keeping seq order. */
export function upsertLot(lots: Lot[], lot: Lot): Lot[] {
  return lots.some((l) => l.seq === lot.seq)
    ? lots.map((l) => (l.seq === lot.seq ? lot : l))
    : [...lots, lot].sort((a, b) => a.seq - b.seq);
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

/**
 * The viewer's own scouted tier for this lot, if they spent their token on
 * it -- never an opponent's, since the rows this client holds are already
 * RLS-scoped to the viewer alone (0159).
 */
export function myScoutHint(hints: ScoutHint[], seq: number, userId: string): ScoutHint | null {
  return hints.find((h) => h.seq === seq && h.user_id === userId) ?? null;
}

/** The viewer's own sealed-round submission for this lot, if they've made one. */
export function mySealedBid(bids: SealedBid[], seq: number, userId: string): SealedBid | null {
  return bids.find((b) => b.seq === seq && b.user_id === userId) ?? null;
}

/** Whether a given seat has locked in a sealed bid for this lot -- presence
 *  only, readable regardless of whose it is (0160's status table). */
export function hasSubmittedSealedBid(statuses: SealedBidStatus[], seq: number, userId: string): boolean {
  return statuses.some((s) => s.seq === seq && s.user_id === userId && s.submitted);
}

/** A player's roster is the slots on the lots they won — there is no roster table. */
export function filledSlots(lots: Lot[], userId: string): Record<Slot, number> {
  const filled: Record<Slot, number> = { ...STANDARD_LIMITS };
  for (const slot of SLOTS) filled[slot] = 0;
  for (const lot of lots) {
    if (lot.winner_id === userId && lot.slot !== null) filled[lot.slot as Slot] += 1;
  }
  return filled;
}

/**
 * What a win on this lot would fill for a given player: their natural slot if
 * it is still open, otherwise FLEX. There is no "choose a slot" step — this is
 * the one unambiguous answer resolve() gives once eligibility has cleared it.
 */
export function targetSlotFor(lot: Lot, filled: Record<Slot, number>, format: AuctionFormat | null): Slot {
  const position = lot.position as Slot;
  return filled[position] < slotLimits(format)[position] ? position : "FLEX";
}

type EligibilityVerdict = { ok: true } | { ok: false; reason: "no_slot" | "flex_would_strand" };

/**
 * A base lot may be bid on by a player whose natural slot for it is still
 * open. Once that slot is full, a flex-eligible position (RB/WR/TE — never
 * QB) may still be bid on for FLEX, but only if enough of this exact position
 * remains undealt to cover every OTHER player who still needs it naturally —
 * counted in remaining slot units, not a headcount of players. That guard
 * replaces "FLEX only in the flex round" as what keeps the board solvable;
 * see the migration and the game doc for the invariant it protects.
 */
function eligibilityFor(
  lot: Lot,
  lots: Lot[],
  players: { user_id: string }[],
  userId: string,
  format: AuctionFormat | null,
): EligibilityVerdict {
  const position = lot.position as Slot;
  const limits = slotLimits(format);
  const mine = filledSlots(lots, userId);
  if (mine[position] < limits[position]) return { ok: true };
  if (position === "QB" || mine.FLEX >= limits.FLEX) return { ok: false, reason: "no_slot" };

  const remaining = lots.filter((l) => l.position === position && l.seq >= lot.seq && l.winner_id === null).length - 1;
  const othersStillNeeding = players
    .filter((p) => p.user_id !== userId)
    .reduce((sum, p) => sum + Math.max(0, limits[position] - filledSlots(lots, p.user_id)[position]), 0);

  return remaining >= othersStillNeeding ? { ok: true } : { ok: false, reason: "flex_would_strand" };
}

export function eligibleFor(lot: Lot, lots: Lot[], players: { user_id: string }[], userId: string, format: AuctionFormat | null): boolean {
  return eligibilityFor(lot, lots, players, userId, format).ok;
}

export function revealedTotal(lots: Lot[], userId: string): number {
  return lots
    .filter((lot) => lot.winner_id === userId)
    .reduce((sum, lot) => sum + Number(lot.points ?? 0), 0);
}

/** Why the controls are off. Null means they are on. */
export type Blocked = "not_your_turn" | "no_slot" | "flex_would_strand" | "passed" | "cannot_afford";

export const BLOCKED_TEXT: Record<Blocked, string> = {
  not_your_turn: "Waiting on another player",
  no_slot: "You have no open slot for this position",
  flex_would_strand: "Someone else still needs this position",
  passed: "You passed on this lot",
  cannot_afford: "You can't afford the next raise",
};

export function blockedReason(args: {
  lot: Lot;
  me: Player | null;
  lots: Lot[];
  players: { user_id: string }[];
  turnSeat: number | null;
  format: AuctionFormat | null;
  passed: boolean;
  price: number;
}): Blocked | null {
  const { lot, me, lots, players, turnSeat, format, passed, price } = args;
  if (!me) return "not_your_turn";
  const verdict = eligibilityFor(lot, lots, players, me.user_id, format);
  if (!verdict.ok) return verdict.reason;
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

/**
 * How many of a player's three single-use abilities (Pass/Scout/Seal) they
 * have left to spend this match, total -- not per-ability. A match dealt
 * before tokens existed has no `format`, and `tokensUsed`-style reads from a
 * seat row default every `used_*_token` to `false`, so both read as the
 * token-count floor (0) and every ability stays unavailable, matching how
 * this feature behaves when it's off.
 */
export function tokensRemaining(format: AuctionFormat | null, me: Pick<Seat, "used_pass_token" | "used_scout_token" | "used_seal_token"> | null): number {
  if (!format || !me) return 0;
  const used = Number(me.used_pass_token) + Number(me.used_scout_token) + Number(me.used_seal_token);
  return Math.max(0, format.tokenCount - used);
}

/** Weekly cards name the player's team before their opponent; season cards show the stable player-season identity. */
export function lotIdentityLine(lot: Lot): string {
  if (lot.week === null || lot.opponent === null) {
    return `${lot.season} · ${lot.team}`;
  }
  return `${lot.season} · Week ${lot.week} · ${lot.team} vs. ${lot.opponent}`;
}

export function matchupLine(lot: Lot): string {
  return `${lot.position} · ${lotIdentityLine(lot)}`;
}

export type WeeklyRevealTier = "rough" | "solid" | "great";

/**
 * A weekly result is only impressive relative to its position. These are PPR
 * breakpoints: a 12-point quarterback day disappoints, while a 12-point tight
 * end day is useful. Season lots deliberately return null; their equivalent
 * needs a server-calculated, position-relative percentile rather than a
 * client-side guess from a single total.
 */
export function weeklyRevealTier(lot: Pick<Lot, "position" | "week" | "opponent" | "points">): WeeklyRevealTier | null {
  if (lot.week === null || lot.opponent === null || lot.points === null) return null;
  const points = Number(lot.points);
  const [rough, great] = lot.position === "QB"
    ? [15, 25]
    : lot.position === "TE"
      ? [8, 16]
      : [10, 20];
  return points < rough ? "rough" : points >= great ? "great" : "solid";
}

export function byPlacement(standings: Standing[]): Standing[] {
  return [...standings].sort(
    (a, b) => (a.placement ?? 99) - (b.placement ?? 99) || Number(b.raw_score) - Number(a.raw_score),
  );
}
